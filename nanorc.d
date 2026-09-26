# the-loft nanorc

# Line numbers
set linenumbers

# Dark-terminal theme: readable labels with cyan accents and blue highlights.
# Use standard ANSI colors for consistent support across fleet hosts.
set numbercolor cyan,normal
set titlecolor brightwhite,blue
set statuscolor brightwhite,blue
set errorcolor brightwhite,red
set selectedcolor brightwhite,blue
set keycolor brightcyan,normal
set functioncolor white,normal

# Show cursor position in status bar
set constantshow

# Use spaces instead of tabs
set tabsize 2
set tabstospaces

# Enable mouse support
set mouse

# Syntax highlighting — include all available definitions
include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/extra/*.nanorc"
