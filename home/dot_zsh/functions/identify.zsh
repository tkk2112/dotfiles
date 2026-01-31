# Function to check if OS is macOS
darwin() {
  [[ "$OSTYPE" == "darwin"* ]]
}

debian() {
  [ -f /etc/debian_version ] || grep -q 'ID=.*debian' /etc/os-release 2>/dev/null
}

fedora() {
  [ -f /etc/fedora-release ] || grep -q 'ID=.*fedora' /etc/os-release 2>/dev/null
}
