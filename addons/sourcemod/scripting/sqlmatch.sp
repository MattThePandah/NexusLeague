#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <SteamWorks>
#include <smjansson>
#include <get5>
#include <socket>
#include <loadmatch>
#include <base64>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX		"[SM]"

Database g_Database = null;

int g_iShotsFired[MAXPLAYERS + 1] = 0;
int g_iShotsHit[MAXPLAYERS + 1] = 0;
int g_iHeadshots[MAXPLAYERS + 1] = 0;

char g_uuidString[64];

//bool g_bLoadMatchAvailable;
bool g_alreadySwapped;

Handle g_hSocket;

/*ConVar g_CVSiteURL;
ConVar g_CVEmbedColour;
ConVar g_CVEmbedAvatar;*/
ConVar g_CVServerIp;
ConVar g_CVServerPort;
//ConVar g_CVWebsocketPass;
ConVar g_CVLeagueID;

//ArrayList ga_sWinningPlayers;
ArrayList ga_iEndMatchVotesT;
ArrayList ga_iEndMatchVotesCT;

Get5State currentMatchState;

public Plugin myinfo = 
{
	name = "SQL Matches",
	author = "DN.H | The Doggy",
	description = "Sends match stats for the current match to a database",
	version = "1.3.1",
	url = "DistrictNine.Host"
};

public void OnPluginStart()
{
	//Create Timer
	CreateTimer(1.0, AttemptMySQLConnection);

	//Hook Events
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("weapon_fire", Event_WeaponFired);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("announce_phase_end", Event_HalfTime);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	//ConVars
	g_CVServerIp = CreateConVar("sqlmatch_websocket_ip", "127.0.0.1", "IP to connect to for sending match end messages.", FCVAR_PROTECTED);
	g_CVServerPort = CreateConVar("sqlmatch_websocket_port", "8889", "Port to connect to for sending match end messages.");
	//g_CVWebsocketPass = CreateConVar("sqlmatch_websocket_pass", "PLEASECHANGEME", "pass for websocket");
	g_CVLeagueID = CreateConVar("sqlmatch_leagueid", "", "League identifier used for renting purposes.", FCVAR_PROTECTED);

	AutoExecConfig(true, "sqlmatch");
	//Initalize ArrayLists
	ga_iEndMatchVotesT = new ArrayList();
	ga_iEndMatchVotesCT = new ArrayList();
	//Register Command

	RegConsoleCmd("sm_gg", Command_EndMatch, "Ends the match once everyone on the team has used it.");
	g_hSocket = SocketCreate(SOCKET_TCP, OnSocketError);

	//Set Socket Options
	SocketSetOption(g_hSocket, SocketReuseAddr, 1);
	SocketSetOption(g_hSocket, SocketKeepAlive, 1);
	SocketSetOption(g_hSocket, ConcatenateCallbacks, 4096);
	SocketSetOption(g_hSocket, DebugMode, 1);

	//Connect Socket
	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();
}

public Action AttemptMySQLConnection(Handle timer)
{
	if (g_Database != null)
	{
		delete g_Database;
		g_Database = null;
	}
	
	char sFolder[32];
	GetGameFolderName(sFolder, sizeof(sFolder));
	if (SQL_CheckConfig("sql_matches"))
	{
		PrintToServer("Initalizing Connection to MySQL Database");
		Database.Connect(SQL_InitialConnection, "sql_matches");
	}
	else
		LogError("Database Error: No Database Config Found! (%s/addons/sourcemod/configs/databases.cfg)", sFolder);
}

public void SQL_InitialConnection(Database db, const char[] sError, int data)
{
	if (db == null)
	{
		CreateTimer(10.0, AttemptMySQLConnection);
		return;
	}
	
	char sDriver[16];
	db.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	if (StrEqual(sDriver, "mysql", false)) LogMessage("MySQL Database: connected");
	
	g_Database = db;
}


void ConnectRelay()
{	
	if (!SocketIsConnected(g_hSocket))
	{
		char sHost[32];
		char sPort[32];
		g_CVServerIp.GetString(sHost, sizeof(sHost));
		g_CVServerPort.GetString(sPort, sizeof(sPort));
		SocketConnect(g_hSocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, sHost, StringToInt(sPort));
	}
	else
		PrintToServer("Socket is already connected?");
}

public Action Timer_Reconnect(Handle timer)
{
	ConnectRelay();
}

void StartReconnectTimer()
{
	if (SocketIsConnected(g_hSocket))
		SocketDisconnect(g_hSocket);
		
	CreateTimer(10.0, Timer_Reconnect);
}

public int OnSocketDisconnected(Handle socket, any arg)
{	
	StartReconnectTimer();
	
	PrintToServer("Socket disconnected");
}

public int OnSocketError(Handle socket, int errorType, int errorNum, any ary)
{
	StartReconnectTimer();
	
	LogError("Socket error %i (errno %i)", errorType, errorNum);
}

public int OnSocketConnected(Handle socket, any arg)
{	
	PrintToServer("Socket Successfully Connected");
}

public int OnSocketReceive(Handle socket, const char[] receiveData, int dataSize, any arg)
{
	PrintToServer(receiveData);
}

public void OnMapStart()
{
	ga_iEndMatchVotesT.Clear();
	ga_iEndMatchVotesCT.Clear();

	if(Get5_GetGameState() == Get5State_Live)
		ServerCommand("get5_endmatch");
}

public void ResetVars(int Client)
{
	if(!IsValidClient(Client)) return;
	g_iShotsFired[Client] = 0;
	g_iShotsHit[Client] = 0;
	g_iHeadshots[Client] = 0;
}


/* This has changed, again :D */
public void Get5_OnGameStateChanged(Get5State oldState, Get5State newState)
{
	currentMatchState = newState;
	if(oldState == Get5State_GoingLive && newState == Get5State_Live)
	{
		char sQuery[1024], sMap[64];
		char sRegion[32], sLeagueID[32];
		GetConVarString(FindConVar("sm_region"), sRegion, sizeof(sRegion));
		g_CVLeagueID.GetString(sLeagueID, sizeof(sLeagueID));
		GetCurrentMap(sMap, sizeof(sMap));
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
				ResetVars(i);
		}

		int teamIndex_T = -1, teamIndex_CT = -1;

		int index = -1;
		while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1)
		{
			int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum");
			if(teamNum == CS_TEAM_T)
			{
				teamIndex_T = index;
			}
			else if (teamNum == CS_TEAM_CT)
			{
				teamIndex_CT = index;
			}
		}

		char teamName_T[32];
		GetEntPropString(teamIndex_T, Prop_Send, "m_szClanTeamname", teamName_T, 32);
		char teamName_CT[32];
		GetEntPropString(teamIndex_CT, Prop_Send, "m_szClanTeamname", teamName_CT, 32);

		int ip[4];
		char pieces[4][8], sIP[32], sPort[32];
		FindConVar("hostport").GetString(sPort, sizeof(sPort));
		SteamWorks_GetPublicIP(ip);

		IntToString(ip[0], pieces[0], sizeof(pieces[]));
		IntToString(ip[1], pieces[1], sizeof(pieces[]));
		IntToString(ip[2], pieces[2], sizeof(pieces[]));
		IntToString(ip[3], pieces[3], sizeof(pieces[]));
		Format(sIP, sizeof(sIP), "%s.%s.%s.%s:%s", pieces[0], pieces[1], pieces[2], pieces[3], sPort);

		GetCurrentMatchId(g_uuidString);
		Format(sQuery, sizeof(sQuery), "INSERT INTO sql_matches_scoretotal (match_id, team_t, team_ct,team_1_name,team_2_name, map, region, league_id, live, server) VALUES ('%s',%i, %i,'%s','%s', '%s', '%s', '%s', 1, '%s');", g_uuidString, CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT),teamName_T,teamName_CT, sMap, sRegion, sLeagueID, sIP);
		g_Database.Query(SQL_InitialInsert, sQuery);

		UpdatePlayerStats();
	}
}

// To be rewritten for UUIDs
public void SQL_InitialInsert(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}
	ServerCommand("tv_record %s", g_uuidString);
}

public void Get5_OnSeriesResult(MatchTeam seriesWinner, int team1MapScore, int team2MapScore)
{
	static float fTime;
	if(GetGameTime() - fTime < 1.0) return;
	fTime = GetGameTime();

	UpdatePlayerStats();
	UpdateMatchStats();
	CreateTimer(45.0, Timer_KickEveryoneEnd); 
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	UpdatePlayerStats(false, GetClientOfUserId(event.GetInt("userid")));
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (Get5_GetGameState() == Get5State_Live)
	{
		UpdateMatchStats();
		UpdatePlayerStats();
		CheckSurrenderVotes();
	}
	else if (Get5_GetGameState() == Get5State_None || Get5State_PostGame)
	{
		UpdateMatchStats();
	}
}

void UpdatePlayerStats(bool allPlayers = true, int Client = 0)
{
	if(Get5_GetGameState() != Get5State_Live) return;

	char sQuery[1024], sName[64], sSteamID[64], sTeamName[64];
	int iEnt, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore;
	iEnt = FindEntityByClassname(-1, "cs_player_manager");

	if(allPlayers)
	{
		Transaction txn_UpdateStats = new Transaction();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true)) continue;

			iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeam", _, i);
			iAlive = GetEntProp(iEnt, Prop_Send, "m_bAlive", _, i);
			iPing = GetEntProp(iEnt, Prop_Send, "m_iPing", _, i);
			iAccount = GetEntProp(i, Prop_Send, "m_iAccount");
			iKills = GetEntProp(iEnt, Prop_Send, "m_iKills", _, i);
			iAssists = GetEntProp(iEnt, Prop_Send, "m_iAssists", _, i);
			iDeaths = GetEntProp(iEnt, Prop_Send, "m_iDeaths", _, i);
			iMVPs = GetEntProp(iEnt, Prop_Send, "m_iMVPs", _, i);
			iScore = GetEntProp(iEnt, Prop_Send, "m_iScore", _, i);

			GetClientName(i, sName, sizeof(sName));
			g_Database.Escape(sName, sName, sizeof(sName));

			GetClientAuthId(i, AuthId_SteamID64, sSteamID, sizeof(sSteamID));

			int len = 0;
			len += Format(sQuery[len], sizeof(sQuery) - len, "INSERT IGNORE INTO sql_matches (match_id, name, steamid, team, alive, ping, account, kills, assists, deaths, mvps, score, disconnected, shots_fired, shots_hit, headshots) ");
			len += Format(sQuery[len], sizeof(sQuery) - len, "VALUES ('%s', '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i, %i, 0, %i, %i, %i) ",g_uuidString, sName, sSteamID, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[i], g_iShotsHit[i], g_iHeadshots[i], sTeamName);
			len += Format(sQuery[len], sizeof(sQuery) - len, "ON DUPLICATE KEY UPDATE name='%s', team=%i, alive=%i, ping=%i, account=%i, kills=%i, assists=%i, deaths=%i, mvps=%i, score=%i, disconnected=0, shots_fired=%i, shots_hit=%i, headshots=%i;", sName, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[i], g_iShotsHit[i], g_iHeadshots[i]);	
			txn_UpdateStats.AddQuery(sQuery);
		}
		g_Database.Execute(txn_UpdateStats, SQL_TranSuccess, SQL_TranFailure);
		return;
	}

	if(!IsValidClient(Client, true)) return;

	iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeam", _, Client);
	iAlive = GetEntProp(iEnt, Prop_Send, "m_bAlive", _, Client);
	iPing = GetEntProp(iEnt, Prop_Send, "m_iPing", _, Client);
	iAccount = GetEntProp(Client, Prop_Send, "m_iAccount");
	iKills = GetEntProp(iEnt, Prop_Send, "m_iKills", _, Client);
	iAssists = GetEntProp(iEnt, Prop_Send, "m_iAssists", _, Client);
	iDeaths = GetEntProp(iEnt, Prop_Send, "m_iDeaths", _, Client);
	iMVPs = GetEntProp(iEnt, Prop_Send, "m_iMVPs", _, Client);
	iScore = GetEntProp(iEnt, Prop_Send, "m_iScore", _, Client);

	GetClientName(Client, sName, sizeof(sName));

	g_Database.Escape(sName, sName, sizeof(sName));
	

	GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));

	int len = 0;
	len += Format(sQuery[len], sizeof(sQuery) - len, "INSERT IGNORE INTO sql_matches (match_id, name, steamid, team, alive, ping, account, kills, assists, deaths, mvps, score, disconnected, shots_fired, shots_hit, headshots) ");
	len += Format(sQuery[len], sizeof(sQuery) - len, "VALUES ('%s', '%s', '%s', %i, %i, %i, %i, %i, %i, %i, %i, %i, 0, %i, %i, %i) ",g_uuidString, sName, sSteamID, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[Client], g_iShotsHit[Client], g_iHeadshots[Client]);
	len += Format(sQuery[len], sizeof(sQuery) - len, "ON DUPLICATE KEY UPDATE name='%s', team=%i, alive=%i, ping=%i, account=%i, kills=%i, assists=%i, deaths=%i, mvps=%i, score=%i, disconnected=0, shots_fired=%i, shots_hit=%i, headshots=%i;", sName, iTeam, iAlive, iPing, iAccount, iKills, iAssists, iDeaths, iMVPs, iScore, g_iShotsFired[Client], g_iShotsHit[Client], g_iHeadshots[Client]);	
	g_Database.Query(SQL_GenericQuery, sQuery);
}

public void SQL_TranSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
	PrintToServer("Transaction Successful");
}

public void SQL_TranFailure(Database db, any data, int numQueries, const char[] sError, int failIndex, any[] queryData)
{
	LogError("Transaction Failed! Error: %s. During Query: %i", sError, failIndex);
}

void UpdateMatchStats()
{
	char sQuery[1024];
	if (Get5_GetGameState() == Get5State_Live)
	{
		Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET team_t=%i, team_ct=%i, live=1 WHERE match_id='%s';", CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT), g_uuidString);
		g_Database.Query(SQL_GenericQuery, sQuery);
	}
	else if (Get5_GetGameState() == Get5State_PostGame || Get5State_None)
	{
		Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET team_t=%i, team_ct=%i, live=0 WHERE match_id='%s';", CS_GetTeamScore(CS_TEAM_T), CS_GetTeamScore(CS_TEAM_CT), g_uuidString);
		g_Database.Query(SQL_EndGame, sQuery);
	}
}

public void SQL_EndGame(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	CloseMatchSocket();
}

public Action Command_EndMatch(int Client, int iArgs)
{
	if(!IsValidClient(Client, true) || Get5_GetGameState() != Get5State_Live) return Plugin_Handled;

	int iTeam = GetClientTeam(Client);

	if(iTeam == CS_TEAM_T)
	{
		if(CS_GetTeamScore(CS_TEAM_CT) - 8 >= CS_GetTeamScore(iTeam)) // Check if CT is 8 or more rounds ahead of T
		{
			if(ga_iEndMatchVotesT.FindValue(Client) == -1) // Check if client has already voted to surrender
			{
				ga_iEndMatchVotesT.Push(Client); // Add client to ArrayList

				int iTeamCount = GetTeamClientCount(iTeam);
				if(ga_iEndMatchVotesT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
				{
					CheckSurrenderVotes();
				}
				else
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true) && GetClientTeam(i) == iTeam)
							PrintToChat(i, "%s %N has voted to surrender, %i/%i votes needed.", PREFIX, Client, ga_iEndMatchVotesT.Length, iTeamCount);
					}
				}
			}
			else PrintToChat(Client, "%s You've already voted to surrender!", PREFIX);
		}
		else PrintToChat(Client, "%s You must be at least 8 rounds behind the enemy team to vote to surrender.", PREFIX);
	}
	else if(iTeam == CS_TEAM_CT)
	{
		if(CS_GetTeamScore(CS_TEAM_T) - 8 >= CS_GetTeamScore(iTeam)) // Check if T is 8 or more rounds ahead of CT
		{
			if(ga_iEndMatchVotesCT.FindValue(Client) == -1) // Check if client has already voted to surrender
			{
				ga_iEndMatchVotesCT.Push(Client); // Add client to ArrayList

				int iTeamCount = GetTeamClientCount(iTeam);
				if(ga_iEndMatchVotesCT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
				{
					CheckSurrenderVotes();
				}
				else
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsValidClient(i, true) && GetClientTeam(i) == iTeam)
							PrintToChat(i, "%s %N has voted to surrender, %i/%i votes needed.", PREFIX, Client, ga_iEndMatchVotesCT.Length, iTeamCount);
					}
				}
			}
			else PrintToChat(Client, "%s You've already voted to surrender!", PREFIX);
		}
		else PrintToChat(Client, "%s You must be at least 8 rounds behind the enemy team to vote to surrender.", PREFIX);
	}
	return Plugin_Handled;
}

public void CheckSurrenderVotes()
{
	int iTeamCount = GetTeamClientCount(CS_TEAM_CT);
	if(iTeamCount <= 1) return;

	if(ga_iEndMatchVotesCT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
				PrintToChat(i, "%s Counter-Terrorists have voted to surrender. Match ending...", PREFIX);
		}

		Get5_OnSeriesResult(Get5_CSTeamToMatchTeam(CS_TEAM_T), 16, CS_GetTeamScore(CS_TEAM_CT));
		CS_TerminateRound(1.0, CSRoundEnd_TerroristsSurrender, false);
		ServerCommand("get5_endmatch");
		UpdateMatchStats();
		ga_iEndMatchVotesCT.Clear(); // Reset the ArrayList
		return;
	}

	iTeamCount = GetTeamClientCount(CS_TEAM_T);
	if(iTeamCount <= 1) return;

	if(ga_iEndMatchVotesT.Length >= iTeamCount) // Check if we have the amount of votes needed to surrender
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
				PrintToChat(i, "%s Terrorists have voted to surrender. Match ending...", PREFIX);
		}

		Get5_OnSeriesResult(Get5_CSTeamToMatchTeam(CS_TEAM_CT), CS_GetTeamScore(CS_TEAM_T), 16);
		CS_TerminateRound(1.0, CSRoundEnd_CTSurrender, false);
		ServerCommand("get5_endmatch");
		UpdateMatchStats();
		ga_iEndMatchVotesT.Clear(); // Reset the ArrayList
		return;
	}
}

// public Action Timer_KickEveryoneSurrender(Handle timer)
// {
// 	UpdateMatchStats();
// 	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) KickClient(i, "Match force ended by surrender vote");
// 	ServerCommand("tv_stoprecord");
// 	return Plugin_Stop;
// }

public void CloseMatchSocket()
{
	char sData[1024], sDataEncoded[2048];

	Handle jsonObj = json_object();
	json_object_set_new(jsonObj, "type", json_integer(1));
	json_object_set_new(jsonObj, "match_id", json_string(g_uuidString));
	json_dump(jsonObj, sData, sizeof(sData), 0, false, false, true);
	CloseHandle(jsonObj);

	if(!SocketIsConnected(g_hSocket))
		ConnectRelay();
	
	EncodeBase64(sDataEncoded, sizeof(sDataEncoded), sData);

	SocketSend(g_hSocket, sDataEncoded, sizeof(sDataEncoded));
}

public Action Timer_KickEveryoneEnd(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) KickClient(i, "Thanks for playing!\nView the match on our website for statistics");
	ServerCommand("tv_stoprecord");
	return Plugin_Stop;
}

public void Event_WeaponFired(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(Get5_GetGameState() != Get5State_Live || !IsValidClient(Client, true)) return;

	int iWeapon = GetEntPropEnt(Client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(iWeapon)) return;

	if(GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType") != -1 && GetEntProp(iWeapon, Prop_Send, "m_iClip1") != 255) g_iShotsFired[Client]++; //should filter knife and grenades
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int Client = GetClientOfUserId(event.GetInt("attacker"));
	if(Get5_GetGameState() != Get5State_Live || !IsValidClient(Client, true)) return;

	if(event.GetInt("hitgroup") >= 0)
	{
		g_iShotsHit[Client]++;
		if(event.GetInt("hitgroup") == 1) g_iHeadshots[Client]++;
	}
}

/* This has changed  */
public void Event_HalfTime(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_alreadySwapped)
    {
    	LogMessage("Event_HalfTime(): Starting team swap...");

        char sQuery[1024];
        int teamIndex_T = -1, teamIndex_CT = -1; 

        int index = -1; 
        while ((index = FindEntityByClassname(index, "cs_team_manager")) != -1) { 
            int teamNum = GetEntProp(index, Prop_Send, "m_iTeamNum"); 
            if (teamNum == CS_TEAM_T) { 
                teamIndex_T = index; 
            } else if (teamNum == CS_TEAM_CT) { 
                teamIndex_CT = index; 
            } 
        }
        
        char teamNameOld_T[32], teamNameOld_CT[32];
        char teamNameNew_T[32], teamNameNew_CT[32];
        GetEntPropString(teamIndex_T, Prop_Send, "m_szClanTeamname", teamNameOld_T, 32);
        GetEntPropString(teamIndex_CT, Prop_Send, "m_szClanTeamname", teamNameOld_CT, 32);

        teamNameNew_T = teamNameOld_CT;
        teamNameNew_CT = teamNameOld_T;

        Format(sQuery, sizeof(sQuery), "UPDATE sql_matches_scoretotal SET team_1_name = '%s', team_2_name = '%s' WHERE match_id = '%s';", teamNameNew_T, teamNameNew_CT, g_uuidString);
        LogMessage("Event_HalfTime(): Setting team_1_name to %s and team_2_name to %s for match_id %s.", teamNameNew_T, teamNameNew_CT, g_uuidString);
        g_Database.Query(SQL_GenericQuery, sQuery);

        // Swap team in database for disconnected players
        Format(sQuery, sizeof(sQuery), "SELECT steamid, team FROM sql_matches WHERE match_id = '%s' AND disconnected=1;", g_uuidString);
        g_Database.Query(SQL_HalfTimeSwap, sQuery);

        g_alreadySwapped = true;
    }
    else
    	LogError("Event_HalfTime(): Teams have already been swapped!");
}

public void SQL_HalfTimeSwap(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}

	if(!results.FetchRow()) return;

	int teamCol, steamCol, team;
	char sSteamID[64], sQuery[256];
	results.FieldNameToNum("team", teamCol);
	results.FieldNameToNum("steamid", steamCol);

	do
	{
		team = results.FetchInt(teamCol);
		results.FetchString(steamCol, sSteamID, sizeof(sSteamID));
		Format(sQuery, sizeof(sQuery), "UPDATE sql_matches SET team=%i WHERE steamid='%s';", team == 2 ? 3 : 2, sSteamID);
		g_Database.Query(SQL_GenericQuery, sQuery);
	} while(results.FetchRow());
}

/* Switching to player_disconnect event */
//	public void OnClientDisconnect(int Client)
//	{
//		if(IsValidClient(Client))
//		{
//			int iIndexT = ga_iEndMatchVotesT.FindValue(Client);
//			int iIndexCT = ga_iEndMatchVotesCT.FindValue(Client);

//			if(iIndexT != -1) ga_iEndMatchVotesT.Erase(iIndexT);
//			if(iIndexCT != -1) ga_iEndMatchVotesCT.Erase(iIndexCT);

//			UpdatePlayerStats(false, Client);

//			CheckSurrenderVotes();
//			ResetVars(Client);

//			if(Get5_GetGameState() == Get5State_Live && IsValidClient(Client, true))
//			{
//				char sQuery[1024], sSteamID[64];
//				GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
//				Format(sQuery, sizeof(sQuery), "UPDATE sql_matches SET disconnected=1 WHERE match_id='%s' AND steamid='%s'", g_uuidString, sSteamID);
//				g_Database.Query(SQL_GenericQuery, sQuery);
//			}
//		}
//	}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	SetEventBroadcast(event, false);
	// If the client isn't valid or isn't currently in a match return
	int Client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(Client, true)) return Plugin_Handled;

	// If the client's steamid isn't valid return
	char sSteamID[64];
	event.GetString("networkid", sSteamID, sizeof(sSteamID));
	if(sSteamID[7] != ':') return Plugin_Handled;
	if(!GetClientAuthId(Client, AuthId_SteamID64, sSteamID, sizeof(sSteamID))) return Plugin_Handled;

	// Find and erase any surrender votes the client has made
	int iIndexT = ga_iEndMatchVotesT.FindValue(Client);
	int iIndexCT = ga_iEndMatchVotesCT.FindValue(Client);

	if(iIndexT != -1) ga_iEndMatchVotesT.Erase(iIndexT);
	if(iIndexCT != -1) ga_iEndMatchVotesCT.Erase(iIndexCT);

	// Update clients stats
	UpdatePlayerStats(false, Client);

	// Recheck surrender votes and reset client vars
	CheckSurrenderVotes();
	ResetVars(Client);

	// If a match is live set the player to disconnected in the database
	if(Get5_GetGameState() == Get5State_Live)
	{
		char sQuery[1024];
		Format(sQuery, sizeof(sQuery), "UPDATE sql_matches SET disconnected=1 WHERE match_id='%s' AND steamid='%s'", g_uuidString, sSteamID);
		g_Database.Query(SQL_GenericQuery, sQuery);
	}
	
	char sReason[50];
	GetEventString(event, "reason", sReason, sizeof(sReason));
	if (StrContains(sReason, "You are not authorised to play this match", false))
	{
		SetEventBroadcast(event, true);
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

//generic query handler
public void SQL_GenericQuery(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
		return;
	}
}


stock bool IsValidClient(int client, bool inPug = false)
{
	if (client >= 1 && 
	client <= MaxClients && 
	IsClientConnected(client) && 
	IsClientInGame(client) &&
	!IsFakeClient(client) &&
	(inPug == false || (Get5_GetGameState() == Get5State_Live && (GetClientTeam(client) == CS_TEAM_CT || GetClientTeam(client) == CS_TEAM_T))))
		return true;
	return false;
}