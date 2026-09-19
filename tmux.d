# the-loft shared tmux config
# Source from ~/.tmux.conf:  source-file /srv/the-loft/tmux.d

# ── Terminal ───────────────────────────────────────────────────────────────────
# setup.sh installs ncurses-term for the tmux-256color terminal definition.
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-kitty:Tc,xterm-256color:Tc"

# ── Behaviour ──────────────────────────────────────────────────────────────────
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -s escape-time 10
set -g focus-events on

# Match bashrc.d's PROMPT_COMMAND: keep the client terminal's tab title useful
set -g set-titles on
set -g set-titles-string "#H: #S:#W"

# ── Splits inherit the current directory ──────────────────────────────────────
bind '"' split-window -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

# ── Status line ────────────────────────────────────────────────────────────────
# Hostname on the left — these are long-lived remote sessions and it is easy to
# forget which host a detached window belongs to.
set -g status-style "bg=colour236,fg=colour250"
set -g status-left " #[bold]#H#[default] "
set -g status-left-length 24
set -g status-right " #S #[fg=colour244]%H:%M "
setw -g window-status-current-style "bold,fg=colour45"
