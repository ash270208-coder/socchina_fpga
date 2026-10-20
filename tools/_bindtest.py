import socket
for port in (6666, 16666, 0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind(("0.0.0.0", port))
        print(f"port {port}: BIND OK -> {s.getsockname()}")
    except OSError as e:
        print(f"port {port}: FAIL {e}")
    finally:
        s.close()
