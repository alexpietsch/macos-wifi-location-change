# Important
Starting with macOS 26, the command `ipconfig getsummary en0` displays the SSID as "\<redacted\>".  
To restore the SSID in the output, you have to run the following command **once**.  

(Reference: [Apple Discussions post](https://discussions.apple.com/thread/256108303?answerId=261575020022#261575020022))
```console
sudo ipconfig setverbose 1
```

# Setup
1. Run `sudo ipconfig setverbose 1` (see above)
2. Run `cp config.example.json config.json`.
3. Add the ssid and location to `config.json` in the format `{"ssid": "<Wifi ssid>", "location": "<exact location name>"},`. See `config.example.json`.
4. _Edit_ .plist file and change L7 to the correct script location.
5. _Copy_ .plist file to `~/Library/LaunchAgents/`:

```console
cp ./dev.alexpts.change-location.plist ~/Library/LaunchAgents/dev.alexpts.change-location.plist
```

5. Load the launch agent using

```console
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.alexpts.change-location.plist
```

## Config
- Logging can be disabled by setting `ENABLE_LOGFILE` to false in `config.json`.
- Each entry in `KNOWN_LOCATIONS` requires `ssid` and `location`. You can optionally add `gateway` (the default-route gateway IP) so the correct location is applied when using Ethernet without Wi-Fi.
- You can optionally add `dns` (for example `["192.168.2.179"]`) to override which DNS servers are applied. If omitted, the script copies DNS from whichever network service already has servers configured in that location (usually Wi-Fi) and applies them to all services, including Ethernet.
- macOS stores DNS per network service in each location. If only Wi-Fi has custom DNS configured in a location, Ethernet will keep using DHCP DNS unless the script applies the same servers to the Ethernet service.
- The default location on MacOS should be "Automatic", and is not depending on your OS language. If your's is different, you can change it via `DEFAULT_LOCATION` in `config.json`. You can check your locations by running:

```zsh
networksetup -listlocations
```

the output should look like this, the first one is the `DEFAULT_LOCATION`:

```console
Automatic
Home
```
