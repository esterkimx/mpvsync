mpvsync
------------
**mpvsync** is a simple playback network synchronization plugin for **mpv**. You can play the same file synchronously with different instances of mpv running on different machines. It will not copy the file itself, so you'll need to obtain a local copy of the file on every device before usage.

Prerequisites
-------------
The plugin uses *luaposix* library for Lua version 5.2. On many popular Linux distributions it could be found in the *lua-posix* package. E.g. on Ubuntu run
```
# apt-get install lua-posix
```

As another option you can use the **luarocks** package manager to install necessary Lua libraries. E.g. on Archlinux there is no *luaposix* package for Lua 5.2, so let's install it using luarocks instead. First of all install luarocks itself for Lua 5.2:
```
# pacman -Syu luarocks-5.2
```
then install librariy:
```
$ luarocks-5.2 install luaposix --local
```
Note that we used *--local* option, so luarocks installed package into *~/.luarocks/* directory instead of the system-wide installation. Now we need to add this directory to *$LUA_PATH* and *$LUA_CPATH* environment variables. This can be done easily with luarocks:
```
$ luarocks-5.2 path
```
It will write values for *$LUA_PATH* and *$LUA_CPATH* to stdout. Just copy it to your shell configuration file.

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

Alternatively, you can pass the script file to mpv with the *--script*:
```
$ mpv --script mpvsync.lua <input-file>
```

Usage
-----
You'll need run one mpv instance as the server and others as the clients. By default mpvsync will listen to port *32923*. Try
```
$ mpv <input-file>
```

After loading the file it should be paused and showing `"Waiting for clients"` on-screen message.
You can specify port with the *mpvsync-port* option (note that to pass options to scripts mpv uses the *--script-opts* key):
```
$ mpv --script-opts=mpvsync-port=58785 <input-file>
```

If you pass *mpvsync-host* option to mpv, it'll run in the client mode. E.g.
```
$ mpv --script-opts=mpvsync-host=localhost <input-file>
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

We can make mpvsync disabled-by-default via the config file:
```
#Example mpvsync configuration file
enabled=no
```

See example config file for futher information. **Be aware of trailing spaces** -- mpv will throw `error converting value` error if you put

```
#Bad
enable=no␣
```

istead of
```
enable=no
```

Examples
--------
Start the mpvsync server listening the port *3535*
```
$ mpv --script-opt=mpvsync-port=3535 <input-file>
```

Start the mpvsync client connected to *example.com:8998*, without OSD notifications
```
$ mpv --script-opt=mpvsync-host=example.com,mpvsync-port=8998,mpvsync-osd=no <input-file>
```

To list options available:
```
$ mpv --script-opts=mpvsync-help=yes -
```
