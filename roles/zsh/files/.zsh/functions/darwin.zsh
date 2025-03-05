# Function to check if OS is macOS
darwin() {
  [[ "$OSTYPE" == "darwin"* ]]
}
