alias ll='ls -l'

if [ ! -d "$HOME/.local/bin" ]; then
  mkdir -p "$HOME/.local/bin"
fi

export PATH="$HOME/.local/bin:$PATH"
