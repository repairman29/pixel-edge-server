echo "=== SSH Config ==="
cat /data/data/com.termux/files/usr/etc/ssh/sshd_config | grep -E "^(AuthorizedKeysFile|Port)"

echo ""
echo "=== Home env ==="
echo "HOME=$HOME"

echo ""
echo "=== SSH dir ==="
ls -la ~/.ssh/

echo ""
echo "=== Authorized keys ==="
cat ~/.ssh/authorized_keys
