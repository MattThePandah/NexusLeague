## Plugin Configuration

### Autoban Plugin

### CVars
```
sm_autoban_fallback_time - Default: 120 - Time a player should be banned for if the MySQL Connection fails to connect.
sm_autoban_websocket_ip - Default: 127.0.0.1 - IP address which the socket is running on.
sm_autoban_package_key - Default: PLEASECHANGEME - The package key / Secret key to communicate with the socket.
sm_autoban_grace_period - Default: 300 - The amount of time a player has to reconnect before being banned for afk / disconnection to the server.
```

### Setup
* Create a database inside your MySQL Server for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.

```
"Databases"
{
	"driver_default"	"mysql"

	"autoban"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"autoban"
		"user"				"user"
		"pass"				"pass"
	}
}
```

### Basic Stats Recording Plugin

### CVars
```
sm_region - Default: N/A - Which region the players are playing on. NA = North America, EU= Europe, OCE = Ocenaic
```

### Setup
* Create a database inside your MySQL Server for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.

```
"Databases"
{
	"driver_default"	"mysql"

	"autoban"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"BasicPlayerStats"
		"user"				"user"
		"pass"				"pass"
	}
}
```

### Elo Plugin (Requires Basic Stats Recording)

### CVars
Any minus values will equal the amount the player will lose.

```
EloSys_DefaultElo - Default: 600 - The default elo which new players will start with.
EloSys_EloPerKill - Default: 2 - The amount of elo a player will receive for each kill.
EloSys_EloPerDeath - Default: -2 - The amount of elo a player will receive for each death
EloSys_EloPerAssist - Default: 1 - The amount of elo a player will receive for each assist.
EloSys_EloPerMVPs - Default: 2 - The amount of elo a player will receive for each MVP.
EloSys_EloPerOneVsTwo - Default: 0 - The amount of elo a player will receive for winning a 1v2 situation.
EloSys_EloPerOneVsThree - Default: 1 - The amount of elo a player will receive for winning a 1v3 situation.
EloSys_EloPerOneVsFour - Default: 2 - The amount of elo a player will receive for winning a 1v4 situation.
EloSys_EloPerOneVsFive - Default: 4 - The amount of elo a player will receive for winning a 1v5 situation.
EloSys_HeadShotKillBonus - Default: 0 - The amount of elo a player will recieve for a headshot kill.
EloSys_EloPerBombExplode - Default: 0 - The amount of elo a player will receive for successful bomb explosion.
EloSys_EloPerBombDisarm - Default: 0 - The amount of elo a player will recieve for a successful bomb defusal.
EloSys_PreliminaryMatchCount - Default: 10 - The amount of preliminary matches played before they are provided with an official Elo value.
EloSys_PrelimMatchEloGain - Default: 125 - The amount of elo which a player will gain on a win. This value will also be used for loss also.
```

### Setup
* Create a database inside your MySQL Server for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.

```
"Databases"
{
	"driver_default"	"mysql"

	"autoban"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"EloSys"
		"user"				"user"
		"pass"				"pass"
	}
}
```

### Force Default Agents

### Setup
* Put the folder playermodels into addons/sourcemod/configs to load the map's config files.

### Ladder Statistics Plugin

### CVars
```
sm_ladder_win - Default: 1 - The amount of points to give/take when a player wins a match.
sm_ladder_tie - Default: 1 - The amount of points to give/take when a player ties a match.
sm_ladder_lose - Default: -1 - The amount of points to give/take when a player loses a match.
sm_ladder_master - Default: -1 - If this is set to 1 the plugin will use this server as the master server to base all other servers ladder dates by.
sm_ladder_start - Default: yyyy-mm-dd - The date at which the stats will start being recorded.
sm_ladder_end - Default: yyyy-mm-dd - The date at which the stats will stop being recorded.
sm_ladder_reset - Default: yyyy-mm-dd - The date at which the stats will be reset.
```

### Setup
* Create a Database inside your MySQL Server (SQLite is not supported) for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.

```
"Databases"
{
	"driver_default"		"mysql"
	
	// When specifying "host", you may use an IP address, a hostname, or a socket file path
	
	"ladder_stats"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"ladder_statistics"
		"user"				"user"
		"pass"				"pass"
	}
}
```

### Load Match Plugin (Requires: SQL Match)

### CVars
```
sqlmatch_websocket_ip - Default: 127.0.0.1 - IP to connect to for sending match end messages.
sqlmatch_websocket_pass - Default: PLEASECHANGEME - Password for websocket.
sm_matchtype - Default: 5v5 - The match type which we are loading and checking the connection for. Options: 1v1, 2v2 or 5v5
```

### SQL Match Plugin
 
### CVars
```
sqlmatch_websocket_ip - Default: 127.0.0.1 - IP to connect to for sending match end messages.
sqlmatch_websocket_pass - Default: PLEASECHANGEME - pass for websocket
sqlmatch_leagueid - Default: "" - League identifier used for renting purposes.
```

### Setup
* Create a Database inside your MySQL Server (SQLite is not supported) for the plugin to use.
* Fill out a section in your databases.cfg (example below) to define the config that the plugin should use.

```
"Databases"
{
	"driver_default"		"mysql"
	
	// When specifying "host", you may use an IP address, a hostname, or a socket file path
	
	"ladder_stats"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"sql_matches"
		"user"				"user"
		"pass"				"pass"
	}
}
```


### Modifications of Get5 Plugin
#### Pause System
#### CVars
* To use this system you will need to edit the ``get5_pause_mode`` within the config to either "Faceit", "Valve" or if left blank will default to Get5 pausing mode. 

##### Valve Pause System
* Valve pausing system: This pause system will use the pause vote which is default within panorama and requires players to vote on if they want to pause or not, this will then use default server settings. The CVars needed to tweak are as follows:

```
sv_allow_votes 1 - **Must be enabled**  
mp_team_timeout_time - This value is how long the time which you want to set on the server.  
mp_team_timeout_max - This is how many timeouts a player can have **Per match**
```

##### FaceIT Pause System
* Faceit pausing system: This pause system was supposed to be designed within Get5 originally but it didn't work correctly, so it was revamped. This pause system requires tweaking of the ``get5_max_pause_time``. This is how long a player can pause in the match. 

##### Default Pause System
* Get5 default pausing: This pause system works very similar to the Get5 original pause system with "Fixed time" pauses. 
* This will use the current cvars set. Please see [Get5](https://github.com/splewis/get5), if you are having issues understanding how this pause system works.  

#### Team Voting System
#### CVars
* To change the voting mode you will need to edit the ``get5_votemode`` value wihin the config to either ESEA or leave blank for default.

##### ESEA Team Voting
* ESEA team voting: This voting mode works similar to how ESEA voting works, for people unfamiliar with ESEA voting the winning team has 60 seconds to all vote on which side they want to be on either t or ct within the chat window. The majority vote wins. 

##### Default Team Voting
* This system follows exactly the same way it currently works via Get5 default or via FaceIT where anyone can type either !stay or !swap.
