# mpvsync

**mpvsync** is a plugin for **mpv** that synchronizes playback over the network, allowing you to play the same file simultaneously on multiple devices running mpv. Each device must have a local copy of the file as the plugin does not transfer the files.

## Prerequisites

The plugin requires the *luaposix* library for Lua version 5.1. On many Linux distributions, this is available in the *lua-posix* package.

Alternatively, use **luarocks** to install Lua libraries. For distributions without a native *luaposix* package for Lua 5.1, you can install it with luarocks.

### ArchLinux

First, install luarocks for Lua 5.1:

```
# pacman -Syu luarocks-5.1
```

Then install *luaposix*:

```
$ luarocks-5.1 install luaposix --local
```

Use the *--local* option to install packages in the *~/.luarocks/* directory. Add this directory to the $LUA_PATH and $LUA_CPATH environment variables:

```
$ luarocks-5.1 path
```

Copy the printed values to your shell configuration file.

### MacOS

First, install luarocks using Homebrew:

```
$ brew install luarocks
```

Lua 5.1 support has been deprecated in Homebrew. To install it, you need to modify the Lua 5.1 formula:

```
$ export HOMEBREW_NO_INSTALL_FROM_API=1
$ brew edit lua@5.1
```

This command may take some time to complete. Once it opens the formula in the editor, find the `disable! ...` line and comment it out.

After modifying the formula, proceed to install Lua 5.1:

```
$ brew install lua@5.1
```

To ensure Lua 5.1 paths are set up correctly in your environment, add them to your `.zshrc` file and then restart your shell:

```
$ luarocks --lua-version=5.1 path >> ~/.zshrc
$ source ~/.zshrc
```
## Installation

Clone the repository:

```
$ git clone https://github.com/esterkimx/mpvsync.git
```

Link the repository to the mpv scripts directory:

```
$ mkdir -p ~/.config/mpv/scripts
$ ln -s mpvsync ~/.config/mpv/scripts
```

Or copy the necessary files:

```
$ cd mpvsync
$ mkdir -p ~/.config/mpv/scripts/mpvsync
$ cp -r main.lua mpvsync_modules ~/.config/mpv/scripts/mpvsync
```

Alternatively, use the *--script* option:

```
$ mpv --script main.lua <input-file>
```

## Usage

Run one instance of mpv as the server and others as clients. By default, mpvsync operates in server mode and listens on port *32923*. Start the server:

```
$ mpv <input-file>
```

The server instance should display "Waiting for clients". To specify a different port, use:

```
$ mpv --script-opts=mpvsync-port=58785 <input-file>
```

To operate in client mode, specify the host:

```
$ mpv --script-opts=mpvsync-host=localhost <input-file>
```

After connecting, the server will control the playback on all clients.

## Configuration

To configure via a file instead of command line, create a configuration directory:

```
$ mkdir -p ~/.config/mpv/lua-settings
```

Create the configuration file:

```
$ $EDITOR ~/.config/mpv/lua-settings/mpvsync.conf
```

To disable mpvsync by default:

```
# Example mpvsync configuration file
enabled=no
```

Note the absence of trailing spaces to avoid errors.

## Examples

Start the server on a specific port:

```
$ mpv --script-opts=mpvsync-port=3535 <input-file>
```

Run a client connected to a specific host and port, without on-screen display notifications:

```
$ mpv --script-opts=mpvsync-host=example.com,mpvsync-port=8998,mpvsync-osd=no <input-file>
```

List all available options:

```
$ mpv --script-opts=mpvsync-help=yes -
```
