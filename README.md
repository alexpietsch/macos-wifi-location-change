# Setup
1. Run `cp config.example.json config.json`.
2. Add the ssid and location to `config.json` in the format `{"ssid": "<Wifi ssid>", "location": "<exact location name>"},`. See `config.example.json`.
3. Edit .plist file and change L7 to the correct script location.
4. Copy .plist file to `~/Library/LaunchAgents/`:

```console
cp ./dev.alexpts.change-location.plist ~/Library/LaunchAgents/dev.alexpts.change-location.plist
```

5. Load the launch agent using

```console
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.alexpts.change-location.plist
```

## Config
- Logging can be disabled by setting `ENABLE_LOGFILE` to false in `config.json`.
- The default location on MacOS should be "Automatic", and is not depending on your OS language. If your's is different, you can change it via `DEFAULT_LOCATION` in `config.json`. You can check your locations by running:

```zsh
networksetup -listlocations
```

the output should look like this, the first one is the `DEFAULT_LOCATION`:

```console
Automatic
Home
```