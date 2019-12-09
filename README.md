# mpvsync

**mpvsync** is a **mpv** plugin for playback synchronization over the network. You can play same file synchronously with different instances of mpv running on different machines. It won't transfer the file itself, so you'd need to obtain a local copy of the file on every device before usage.

Prerequisites
-------------
The plugin requires *luaposix* library for Lua version 5.2. On many popular Linux distributions it could be found in the *lua-posix* package. To install it on Ubuntu run
```
# apt-get install lua-posix
```

Other way is to use **luarocks** package manager to install necessary Lua libraries. For example, on Archlinux there is no *luaposix* package for Lua 5.2, so let's install it using luarocks instead. First, install luarocks for Lua 5.2:
```
# pacman -Syu luarocks-5.2
```
then install *luaposix*:
```
$ luarocks-5.2 install luaposix --local
```
Note that we're using *--local* option, so luarocks installs packages into *~/.luarocks/* directory. Now we need to add this directory to $LUA_PATH and $LUA_CPATH environment variables:
```
$ luarocks-5.2 path
```
This will print values for $LUA_PATH and $LUA_CPATH. Copy it to your shell configuration file.

Installation
------------
Clone this repository
```
$ git clone https://github.com/esterkimx/mpvsync.git
```

then copy *mpvsync.lua* and *mpvsync_modules* to the mpv *scripts* directory:
```
$ cd mpvsync
$ mkdir -p ~/.config/mpv/scripts
$ cp -r mpvsync.lua mpvsync_modules ~/.config/mpv/scripts/
```

Alternatively, you can set the script file with *--script*:
```
$ mpv --script mpvsync.lua <input-file>
```

Usage
-----
You'll need to run one mpv instance as the server and others as clients. By default mpvsync will run as the server and listen to port *32923*. Run
```
$ mpv <input-file>
```

The file should be paused and mpv should be displaying `"Waiting for clients"` on-screen message.
You can specify port with the *mpvsync-port* option (note that we use *--script-opts* to pass options to plugins):
```
$ mpv --script-opts=mpvsync-port=58785 <input-file>
```

To run mpvsyn in client mode, add *mpvsync-host* option to mpvsync.
```
$ mpv --script-opts=mpvsync-host=localhost <input-file>
```

After connection is established the server will control clients' playbacks.

Configuration
-------------
Instead of passing all options with *--scripts-opts*, we can use configuration file. Create a *lua-settings* directory in the mpv config directory:
```
$ mkdir -p ~/.config/mpv/lua-settings
```

Now we can create a config file there:
```
$ $EDITOR ~/.config/mpv/lua-settings/mpvsync.conf
```

We can make mpvsync disabled by default via the config file:
```
#Example mpvsync configuration file
enabled=no
```

See example config file `mpvsync.conf` for futher information. **Be aware of trailing spaces** -- mpv will throw `error converting value` if you put

```
#Bad
enable=no␣
```

instead of
```
enable=no
```

Examples
--------
Start the server listening the port *3535*
```
$ mpv --script-opt=mpvsync-port=3535 <input-file>
```

Run a client connected to *example.com:8998*, without OSD notifications
```
$ mpv --script-opt=mpvsync-host=example.com,mpvsync-port=8998,mpvsync-osd=no <input-file>
```

List available opitons
```
$ mpv --script-opts=mpvsync-help=yes -
```
