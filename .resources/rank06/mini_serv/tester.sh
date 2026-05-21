#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USER_C="../../../rendu/mini_serv/mini_serv.c"
BIN="./temp_mini_serv"
PORT=42424
SERVER_PID=""

fail() {
    echo -e "${RED}❌ $1${NC}"
    cleanup
    exit 1
}

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    rm -f "$BIN"
}

trap cleanup EXIT INT TERM

echo -e "${BLUE}🔍 Running tests for mini_serv${NC}"
echo "=========================================="

if [ ! -f "$USER_C" ]; then
    fail "User solution not found: $USER_C"
fi

echo -e "${BLUE}📦 Test 1: Compilation${NC}"

gcc -Wall -Wextra -Werror "$USER_C" -o "$BIN" 2> compile_error.log
if [ $? -ne 0 ]; then
    cat compile_error.log
    rm -f compile_error.log
    fail "Compilation failed"
fi
rm -f compile_error.log

echo -e "${GREEN}✅ Compilation successful${NC}"
echo ""

echo -e "${BLUE}📦 Test 2: Forbidden preprocessor define${NC}"

if grep -q '^[[:space:]]*#define' "$USER_C"; then
    fail "Forbidden #define found"
fi

echo -e "${GREEN}✅ No #define found${NC}"
echo ""

echo -e "${BLUE}📦 Test 3: Required functions presence${NC}"

required_funcs=("socket" "bind" "listen" "accept" "select" "recv" "send" "close")
missing=0

for func in "${required_funcs[@]}"; do
    if grep -q "\b$func\b" "$USER_C"; then
        echo -e "${GREEN}✅ Found: $func${NC}"
    else
        echo -e "${RED}❌ Missing: $func${NC}"
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    fail "Missing required functions"
fi

echo ""

echo -e "${BLUE}📦 Test 4: Wrong number of arguments${NC}"

set +e
err_output=$("$BIN" 2>&1 >/dev/null)
status=$?
set -e

if [ "$status" -ne 1 ]; then
    fail "Expected exit status 1 without arguments, got $status"
fi

if [ "$err_output" != "Wrong number of arguments" ]; then
    echo "Got stderr: [$err_output]"
    fail "Expected exact stderr: Wrong number of arguments"
fi

echo -e "${GREEN}✅ Wrong argument handling OK${NC}"
echo ""

echo -e "${BLUE}📦 Test 5: Runtime client/server behavior${NC}"

"$BIN" "$PORT" &
SERVER_PID=$!

sleep 0.3

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "Server exited immediately"
fi

python3 - "$PORT" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])

def fail(msg):
    print("❌ " + msg)
    sys.exit(1)

def connect_client():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(("127.0.0.1", port))
    return s

def recv_until(sock, expected, label):
    data = b""
    deadline = time.time() + 2

    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                fail(label + ": connection closed")
            data += chunk
            if expected in data:
                return data
        except socket.timeout:
            pass

    fail(label + ": expected %r, got %r" % (expected, data))

def assert_no_data(sock, label):
    sock.settimeout(0.3)
    try:
        data = sock.recv(4096)
        if data:
            fail(label + ": unexpected data %r" % data)
    except socket.timeout:
        return

c0 = connect_client()
c1 = connect_client()

recv_until(c0, b"server: client 1 just arrived\n", "client 0 arrival notification")

c2 = connect_client()

recv_until(c0, b"server: client 2 just arrived\n", "client 0 second arrival notification")
recv_until(c1, b"server: client 2 just arrived\n", "client 1 second arrival notification")

c1.sendall(b"hello\nworld\n")

expected = b"client 1: hello\nclient 1: world\n"

recv_until(c0, expected, "client 0 broadcast")
recv_until(c2, expected, "client 2 broadcast")

assert_no_data(c1, "sender should not receive own message")

c2.close()

recv_until(c0, b"server: client 2 just left\n", "client 0 leave notification")
recv_until(c1, b"server: client 2 just left\n", "client 1 leave notification")

c0.close()
c1.close()

print("✅ Runtime behavior OK")
PY

if [ $? -ne 0 ]; then
    fail "Runtime behavior failed"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}PASSED 🎉${NC}"
exit 0