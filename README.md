mpvsync
------------
**mpvsync** is a simple playback network synchronization plugin for **mpv**. You can play same file synchronously with different instances of mpv running on different machines. It will not copy the file itself, so you'll need to obtain a local copy on every device before usage.

Prerequisites
-------------
The plugin uses luasocket library for Lua 5.2. On many popular Linux distributions it could be found in the package `lua-socket`. E.g. on Ubuntu run `
```
# apt-get install lua-socket
```

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
$ cp -r mpvsync.lua mpvsync_modules ~/.config/mpv/scripts
```

Alternatively, you can pass the script file to mpv with the *--script* option without installation:
```
$ mpv --script mpvsync.lua
```

Usage
-----
You need one mpv instance running as the server and others as the clients. After the installation mpvsync will listening on the port *32923*. Try
```
$ mpv --script-opts=mpvsync-enabled=yes <input-file>
```

After loading the file it should be paused and showing "Waiting for clients" on-screen message.
You can specify port with the *mpvsync-port* option (note that to pass options to scripts mpv uses the *--script-opts* option):
```
$ mpv --script-opts=mpvsync-enabled=yes,mpvsync-port=58785 <input-file>
```

If you pass *mpvsync-host* option to mpv, it'll run in the client mode. E.g.
```
$ mpv --script-opts=mpvsync-enabled=yes,mpvsync-host=localhost <input-file>
```

After connection is established the server will control the clients' playbacks.

Configuration
-------------
We can configure mpvsync via configure file instead of passing all options with the *--scripts-opts*. To do so we need to make directory *lua-settings* in the mpv config directory:
```
$ mkdir -p ~/.config/mpv/lua-settings
```

Now we can put config file there:
```
$ $EDITOR ~/.config/mpv/lua-settings/mpvsync.conf
```

mpvsync disabled by default and we need to pass the *mpvsync-enabled=yes* option.
We can make it enabled-by-default via the config file:
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

Example
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
