mpvsync
------------
**mpvsync** is a simple playback network synchronization plugin for **mpv**. You can play the same file synchronously with different instances of mpv running on different machines. It will not copy the file itself, so you'll need to obtain a local copy of the file on every device before usage.

Prerequisites
-------------
The plugin uses *luaposix* library for Lua version 5.2. On many popular Linux distributions it could be found in the *lua-posix* package. E.g. on Ubuntu run
```
# apt-get install lua-posix
```

As another option you can use the **luarocks** package manager to install necessary lua libraries. E.g. on Archlinux there is no *luaposix* package for Lua 5.2, so let's install it using luarocks instead. First of all install luarocks itself for Lua 5.2:
```
# pacman -Syu luarocks-5.2
```
then install librariy:
```
$ luarocks-5.2 install luaposix --local
```
Note that we used *--local* option, so luarocks installed packages into *~/.luarocks/* directory instead of the system-wide installation. So now we need to add this directory to *$LUA_PATH* and *$LUA_CPATH* environment variables. We can do it easily with luarocks, run
```
$ luarocks-5.2 path
```
It will write to stdout export values for *$LUA_PATH* and *$LUA_CPATH*. Just copy it to your shell's configuration file (i.e. *~/.bashrc* or *~/.zshrc*)

Installation
------------
Clone this repository
```
$ git clone https://github.com/esterkimx/mpvsync.git
```

then copy *mpvsync.lua* and *mpvsync_modules* to the mpv scripts directory:
```
$ cd mpvsync
$ mkdir -p ~/.config/mpv/scripts
$ cp -r mpvsync.lua mpvsync_modules ~/.config/mpv/scripts/
```

Alternatively, you can pass the script file to mpv with the *--script* option without installation:
```
$ mpv --script mpvsync.lua
```

Usage
-----
You need one mpv instance running as the server and others as the clients. By default mpvsync will listen to the port *32923*. Try
```
$ mpv --script-opts=mpvsync-enabled=yes <input-file>
```

After loading the file it should be paused and showing `"Waiting for clients"` on-screen message.
You can specify port with the *mpvsync-port* option (note that to pass options to scripts mpv uses the *--script-opts* key):
```
$ mpv --script-opts=mpvsync-enabled=yes,mpvsync-port=58785 <input-file>
```

If you pass *mpvsync-host* option to mpv, it'll run in the client mode. E.g.
```
$ mpv --script-opts=mpvsync-enabled=yes,mpvsync-host=localhost <input-file>
```

After the connection is established the server will control the clients' playbacks.

Configuration
-------------
We can configure mpvsync via configuration file instead of passing all options with the *--scripts-opts*. To do so we need to create *lua-settings* directory in the mpv config directory:
```
$ mkdir -p ~/.config/mpv/lua-settings
```

Now we can put config file there:
```
$ $EDITOR ~/.config/mpv/lua-settings/mpvsync.conf
```

mpvsync disabled by default and we need to pass the *mpvsync-enabled=yes* option to use it. We can make it enabled-by-default via the config file:
```
#Example mpvsync configuration file
enabled=yes
```

Additionally, we can turn-off pause in the beginning of the playback:
```
#Example mpvsync configuration file
enabled=yes
wait=no
```

Examples
--------
Start the mpvsync server listening the port *3535* without mpvsync installation
```
$ mpv --script mpvsync.lua --script-opt=mpvsync-port=3535
```

Start the mpvsync client connected to *example.com:8998*, without OSD notifications
```
$ mpv --script-opt=mpvsync-host=example.com,mpvsync-port=8998,mpvsync-osd=no
```

To list options available:
```
$ mpv --script mpvsync.lua --script-opts=mpvsync-help=yes -
```
