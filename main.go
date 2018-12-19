package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	libs "github.com/vadv/gopher-lua-libs"
	lua "github.com/yuin/gopher-lua"
)

var (
	BuildVersion = "unknown"
	version      = flag.Bool("version", false, "print version and exit")
	confFile     = flag.String("script", "/etc/zbx4tg.lua", "path to script file")
)

func main() {

	if !flag.Parsed() {
		flag.Parse()
	}
	if *version {
		fmt.Printf("%s\n", BuildVersion)
		os.Exit(1)
	}

	state := lua.NewState()
	libs.Preload(state)
	for {
		if err := state.DoFile(*confFile); err != nil {
			log.Printf("[FATAL] %s\n", err.Error())
			os.Exit(2)
		}
		time.Sleep(time.Second)
	}
}
