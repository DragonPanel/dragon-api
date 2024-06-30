# Dragon API - HTTP API for Linux & Systemd
## Very WIP

This project started because I wanted to learn Zig.  
And what is the better way of learning zig than to build something to interact with low-level Linux stuff?  
So I am mixing it all to learn more about systemd, Linux and programming in low level language ^^

## Run project
All you need to do is clone this repo and run:
```sh
zig build run
```

### This project depends on glibc and obviously systemd!

## Planned features
* [x] Journald logs reading
* [x] Units management with systemd
* [ ] Resources monitor
* [ ] Processes management
* [ ] User management
* [ ] Writing to STDIO of selected process! (If it's possible lol)
* [ ] <del>Filesystem access</del>
* [ ] Minimal HTTP proxy (to proxy Caddy admin for example)
* [ ] Docker???

## TODO (so I know what to do next lol)
* [x] systemctl enable, disable
* [x] systemctl daemon-reload
* [ ] custom dispatcher for http.zig to handle errors like `err.UnexpectedToken` if JSON type is invalid and give some meaningful error description.
* [ ] `/v1/systemd/manager`
* [ ] `/v1/systemd/journal`
* [ ] system resources
* [ ] process list, hell yeah, let's get to /proc
* [x] unification of api errors, need to make it right.
* [ ] systemctl start transient
* [ ] advanced journal filtering
* [ ] live journal with websockets

# License
AGPLv3
