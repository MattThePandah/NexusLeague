#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

Database g_Database = null;

float g_fDelay = 0.0;

ArrayList ga_sCurrentPlayers;

bool g_bLadderEnabled = false;

char g_sConVars[3][16];

ConVar g_hCVWinPoints;
ConVar g_hCVLosePoints;
ConVar g_hCVTiePoints;
ConVar g_hCVMasterServer;
ConVar g_hCVStartDate;
ConVar g_hCVEndDate;
ConVar g_hCVResetDate;

public Plugin myinfo = 
{
	name = "Player Ladder", 
	author = "DN.H | The Doggy", 
	description = "Stores ladder statistics for players", 
	version = "1.2.0",
	url = "DistrictNine.Host"
};

public void OnPluginStart()
{
	CreateTimer(1.0, AttemptMySQLConnection);
	ga_sCurrentPlayers = new ArrayList(64);

	g_hCVWinPoints = CreateConVar("sm_ladder_win", "1", "The amount of points to give/take when a player wins a match.");
	g_hCVTiePoints = CreateConVar("sm_ladder_tie", "1", "The amount of points to give/take when a player ties a match.");
	g_hCVLosePoints = CreateConVar("sm_ladder_lose", "-1", "The amount of points to give/take when a player loses a match.");
	g_hCVMasterServer = CreateConVar("sm_ladder_master", "-1", "If this is set to 1 the plugin will use this server as the master server to base all other servers ladder dates by.");
	g_hCVStartDate = CreateConVar("sm_ladder_start", "yyyy-mm-dd", "The date at which the stats will start being recorded.");
	g_hCVStartDate.AddChangeHook(ConVar_DateChanged);
	g_hCVEndDate = CreateConVar("sm_ladder_end", "yyyy-mm-dd", "The date at which the stats will stop being recorded.");
	g_hCVEndDate.AddChangeHook(ConVar_DateChanged);
	g_hCVResetDate = CreateConVar("sm_ladder_reset", "yyyy-mm-dd", "The date at which the stats will be reset.");
	g_hCVResetDate.AddChangeHook(ConVar_DateChanged);
}

public void OnMapStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("cs_win_panel_match", Event_MatchEnd);
	HookEvent("player_team", Event_ChangeTeam);

	g_hCVStartDate.GetString(g_sConVars[0], sizeof(g_sConVars[]));
	g_hCVEndDate.GetString(g_sConVars[1], sizeof(g_sConVars[]));
	g_hCVResetDate.GetString(g_sConVars[2], sizeof(g_sConVars[]));
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
	if (SQL_CheckConfig("ladder_stats"))
	{
		PrintToServer("Initalizing Connection to MySQL Database");
		Database.Connect(SQL_InitialConnection, "ladder_stats");
	}
	else
		LogError("Database Error: No Database Config Found! (%s/addons/sourcemod/configs/databases.cfg)", sFolder);

	return Plugin_Handled;
}

public void SQL_InitialConnection(Database db, const char[] sError, int data)
{
	if (db == null)
	{
		LogMessage("Database Error: %s", sError);
		CreateTimer(10.0, AttemptMySQLConnection);
		return;
	}
	
	char sDriver[16];
	db.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	if (StrEqual(sDriver, "mysql", false)) LogMessage("MySQL Database: connected");
	
	g_Database = db;
	CreateAndVerifySQLTables();
	InsertConVarValues();
	CheckDate();
	CreateTimer(86400.0, CheckDateTimer, _, TIMER_REPEAT); // Check dates once every day (86400 seconds = 1 day)
}

public void CreateAndVerifySQLTables()
{
	char sQuery[1024] = "";
	StrCat(sQuery, 1024, "CREATE TABLE IF NOT EXISTS ladder_stats (");
	StrCat(sQuery, 1024, "steamid64 VARCHAR(64) NOT NULL, ");
	StrCat(sQuery, 1024, "team INTEGER NOT NULL, ");
	StrCat(sQuery, 1024, "points INTEGER NOT NULL DEFAULT 0, ");
	StrCat(sQuery, 1024, "PRIMARY KEY(steamid64));");
	g_Database.Query(SQL_GenericQuery, sQuery);

	sQuery = "";
	StrCat(sQuery, 1024, "CREATE TABLE IF NOT EXISTS ladder_settings (");
	StrCat(sQuery, 1024, "start_date VARCHAR(16) NOT NULL, ");
	StrCat(sQuery, 1024, "end_date VARCHAR(16) NOT NULL, ");
	StrCat(sQuery, 1024, "reset_date VARCHAR(16) NOT NULL);");
	g_Database.Query(SQL_GenericQuery, sQuery);
}

public void InsertConVarValues()
{
	if(g_hCVMasterServer.IntValue == 1)
	{
		if(StrEqual(g_sConVars[0], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_start\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}
		else if(StrEqual(g_sConVars[1], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_end\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}
		else if(StrEqual(g_sConVars[2], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_reset\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}

		char sQuery[1024];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM ladder_settings;");
		g_Database.Query(SQL_CheckSettings, sQuery);
	}
}

public void SQL_CheckSettings(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
	}

	// Row already exists so don't insert new one
	if(results.FetchRow()) return;

	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), "INSERT INTO ladder_settings VALUES ('%s', '%s', '%s');", g_sConVars[0], g_sConVars[1], g_sConVars[2]);
	g_Database.Query(SQL_GenericQuery, sQuery);
}

public Action CheckDateTimer(Handle hTimer)
{
	CheckDate();
	return Plugin_Continue;
}

public void CheckDate()
{
	char sQuery[1024] = "SELECT CURDATE() date;";
	g_Database.Query(SQL_CheckDate, sQuery);
}

public void SQL_CheckDate(Database db, DBResultSet results, const char[] sError, any data)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
	}

	if(!results.FetchRow()) return;

	int dateCol;
	results.FieldNameToNum("date", dateCol);

	char sBuffer[32], sDates[3][16];
	results.FetchString(dateCol, sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, "-", sDates, sizeof(sDates), sizeof(sDates[]));

	int curYear, curMonth, curDay;
	curYear = StringToInt(sDates[0]);
	curMonth = StringToInt(sDates[1]);
	curDay = StringToInt(sDates[2]);

	if(g_hCVMasterServer.IntValue == 1)
	{
		if(StrEqual(g_sConVars[0], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_start\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}
		else if(StrEqual(g_sConVars[1], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_end\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}
		else if(StrEqual(g_sConVars[2], "yyyy-mm-dd"))
		{
			LogError("ConVar \"sm_ladder_reset\" not set, plugin will not run.");
			g_bLadderEnabled = false;
			return;
		}

		char sStartDates[3][16], sEndDates[3][16], sResetDates[3][16];
		ExplodeString(g_sConVars[0], "-", sStartDates, sizeof(sStartDates), sizeof(sStartDates[]));
		ExplodeString(g_sConVars[1], "-", sEndDates, sizeof(sEndDates), sizeof(sEndDates[]));
		ExplodeString(g_sConVars[2], "-", sResetDates, sizeof(sResetDates), sizeof(sResetDates[]));

		int startYear, startMonth, startDay, endYear, endMonth, endDay, resetYear, resetMonth, resetDay;
		startYear = StringToInt(sStartDates[0]);
		startMonth = StringToInt(sStartDates[1]);
		startDay = StringToInt(sStartDates[2]);

		endYear = StringToInt(sEndDates[0]);
		endMonth = StringToInt(sEndDates[1]);
		endDay = StringToInt(sEndDates[2]);

		resetYear = StringToInt(sResetDates[0]);
		resetMonth = StringToInt(sResetDates[1]);
		resetDay = StringToInt(sResetDates[2]);

		int curTimestamp = GetTimestamp(curYear, curMonth, curDay);
		int startTimestamp = GetTimestamp(startYear, startMonth, startDay);
		int endTimestamp = GetTimestamp(endYear, endMonth, endDay);
		int resetTimestamp = GetTimestamp(resetYear, resetMonth, resetDay);

		if(curTimestamp >= resetTimestamp)
			ResetLadder();

		if(curTimestamp >= startTimestamp && curTimestamp < endTimestamp)
			g_bLadderEnabled = true;
		else
			g_bLadderEnabled = false;
	}
	else
	{
		DataPack pack = new DataPack();
		pack.WriteCell(curYear);
		pack.WriteCell(curMonth);
		pack.WriteCell(curDay);

		char sQuery[1024] = "SELECT * FROM ladder_settings;";
		g_Database.Query(SQL_SelectDates, sQuery, pack);
	}
}

public void SQL_SelectDates(Database db, DBResultSet results, const char[] sError, DataPack pack)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
	}

	if(!results.FetchRow())
	{
		LogError("Please change sm_ladder_master to 1 if you have no other servers running this plugin.");
		return;
	}

	pack.Reset();
	int curYear, curMonth, curDay;
	curYear = pack.ReadCell();
	curMonth = pack.ReadCell();
	curDay = pack.ReadCell();

	int curTimestamp = GetTimestamp(curYear, curMonth, curDay);
	int startTimestamp;
	int endTimestamp;
	int resetTimestamp;

	int startCol;
	int endCol;
	int resetCol;

	results.FieldNameToNum("start_date", startCol);
	results.FieldNameToNum("end_date", endCol);
	results.FieldNameToNum("reset_date", resetCol);

	char sBuffer[32], sStartDates[3][16], sEndDates[3][16], sResetDates[3][16];

	results.FetchString(startCol, sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, "-", sStartDates, sizeof(sStartDates), sizeof(sStartDates[]));

	results.FetchString(endCol, sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, "-", sEndDates, sizeof(sEndDates), sizeof(sEndDates[]));

	results.FetchString(resetCol, sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, "-", sResetDates, sizeof(sResetDates), sizeof(sResetDates[]));

	int startDay, startMonth, startYear, endDay, endMonth, endYear, resetDay, resetMonth, resetYear;

	startYear = StringToInt(sStartDates[0]);
	startMonth = StringToInt(sStartDates[1]);
	startYear = StringToInt(sStartDates[2]);

	endYear = StringToInt(sEndDates[0]);
	endMonth = StringToInt(sEndDates[1]);
	endDay = StringToInt(sEndDates[2]);

	resetYear = StringToInt(sResetDates[0]);
	resetMonth = StringToInt(sResetDates[1]);
	resetDay = StringToInt(sResetDates[2]);

	startTimestamp = GetTimestamp(startYear, startMonth, startDay);
	endTimestamp = GetTimestamp(endYear, endMonth, endDay);
	resetTimestamp = GetTimestamp(resetYear, resetMonth, resetDay);

	if(curTimestamp >= resetTimestamp)
		ResetLadder();

	if(curTimestamp >= endTimestamp)
	{
		g_bLadderEnabled = false;
		return;
	}

	if(curTimestamp >= startTimestamp && curTimestamp < endTimestamp)
		g_bLadderEnabled = true;
}

public void ResetLadder()
{
	char sQuery[1024] = "DELETE FROM ladder_stats;";
	g_Database.Query(SQL_GenericQuery, sQuery);
}

public void ConVar_DateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(g_Database == null) return;

	if(g_hCVMasterServer.IntValue == 1)
	{
		char sName[32], sQuery[1024];
		convar.GetName(sName, sizeof(sName));

		if(StrEqual(sName, "sm_ladder_start")) 
		{
			Format(g_sConVars[0], sizeof(g_sConVars[]), "%s", newValue);
			Format(sQuery, sizeof(sQuery), "UPDATE ladder_settings SET start_date = '%s';", g_sConVars[0]);
		}
		else if(StrEqual(sName, "sm_ladder_end"))
		{
			Format(g_sConVars[1], sizeof(g_sConVars[]), "%s", newValue);
			Format(sQuery, sizeof(sQuery), "UPDATE ladder_settings SET end_date = '%s';", g_sConVars[1]);
		}
		else if(StrEqual(sName, "sm_ladder_reset"))
		{
			Format(g_sConVars[2], sizeof(g_sConVars[]), "%s", newValue);
			Format(sQuery, sizeof(sQuery), "UPDATE ladder_settings SET reset_date = '%s';", g_sConVars[2]);
		}
		g_Database.Query(SQL_GenericQuery, sQuery);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if(g_bLadderEnabled)
	{
		if(GetGameTime() - g_fDelay <= 1.0 || GameRules_GetProp("m_bWarmupPeriod") == 1) return; //for some reason round_start is still being called twice during the match, however it shouldn't cause any problems so ¯\_(ツ)_/¯
		g_fDelay = GetGameTime();

		Transaction txn_InsertTrans = new Transaction();
		char sQuery[1024], sSteam[64];
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i) && (GetClientTeam(i) == CS_TEAM_T || GetClientTeam(i) == CS_TEAM_CT))
			{
				GetClientAuthId(i, AuthId_SteamID64, sSteam, sizeof(sSteam));
				if(ga_sCurrentPlayers.FindString(sSteam) == -1) //deny duplicates
					ga_sCurrentPlayers.PushString(sSteam);

				Format(sQuery, sizeof(sQuery), "INSERT IGNORE INTO ladder_stats (steamid64, team) VALUES ('%s', %i) ON DUPLICATE KEY UPDATE team=%i;", sSteam, GetClientTeam(i), GetClientTeam(i));
				txn_InsertTrans.AddQuery(sQuery);
			}
		}
		g_Database.Execute(txn_InsertTrans, SQL_TranSuccess, SQL_TranFailure);

		UnhookEvent("round_start", Event_RoundStart);
	}
}

public void SQL_TranSuccess(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
	PrintToServer("Transaction Successful");
}

public void SQL_TranFailure(Database db, any data, int numQueries, const char[] sError, int failIndex, any[] queryData)
{
	LogError("Transaction Failed! Error: %s. During Query: %i", sError, failIndex);
}

public void Event_MatchEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(g_bLadderEnabled)
	{
		if(GetGameTime() - g_fDelay <= 1.0) return; //More double call protection, still not sure why it's even happening
		g_fDelay = GetGameTime();

		int iTScore = CS_GetTeamScore(CS_TEAM_T);
		int iCTScore = CS_GetTeamScore(CS_TEAM_CT);

		char sQuery[1024], sQuery1[1024], sSteam[64];
		for(int i = 0; i < ga_sCurrentPlayers.Length; i++)
		{
			ga_sCurrentPlayers.GetString(i, sSteam, sizeof(sSteam));

			if(iTScore > iCTScore)
			{
				Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVWinPoints.IntValue, CS_TEAM_T, sSteam);
				Format(sQuery1, sizeof(sQuery1), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVLosePoints.IntValue, CS_TEAM_CT, sSteam);
			}
			else if(iCTScore > iTScore)
			{
				Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVWinPoints.IntValue, CS_TEAM_CT, sSteam);
				Format(sQuery1, sizeof(sQuery1), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVLosePoints.IntValue, CS_TEAM_T, sSteam);
			}
			else
			{
				Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVTiePoints.IntValue, CS_TEAM_T, sSteam);
				Format(sQuery1, sizeof(sQuery1), "UPDATE ladder_stats SET points=points+%i WHERE team=%i AND steamid64='%s';", g_hCVTiePoints.IntValue, CS_TEAM_CT, sSteam);
			}

			g_Database.Query(SQL_GenericQuery, sQuery);
			g_Database.Query(SQL_GenericQuery, sQuery1);
		}
	}
}

public void Event_ChangeTeam(Event event, const char[] name, bool dontBroadcast)
{
	if(g_bLadderEnabled)
	{
		static int iTimes;
		int Client = GetClientOfUserId(event.GetInt("userid"));

		char sQuery[1024], sSteam[64];
		GetClientAuthId(Client, AuthId_SteamID64, sSteam, sizeof(sSteam));
		Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET team=%i WHERE team=%i AND steamid64='%s';", event.GetInt("team"), event.GetInt("oldteam"), sSteam);
		g_Database.Query(SQL_GenericQuery, sQuery);

		if(iTimes == 0 && event.GetBool("autoteam"))
		{
			for(int i = 0; i < ga_sCurrentPlayers.Length; i++)
			{
				ga_sCurrentPlayers.GetString(i, sSteam, sizeof(sSteam));
				for(int j = 1; j <= MaxClients; j++)
				{
					if(!IsValidClient(j)) continue;

					char sJSteam[64];
					GetClientAuthId(j, AuthId_SteamID64, sJSteam, sizeof(sJSteam));

					if(StrEqual(sSteam, sJSteam)) continue;
					else
					{
						Format(sQuery, sizeof(sQuery), "SELECT team FROM ladder_stats WHERE steamid64='%s';", sSteam);
						DataPack pack = new DataPack();
						pack.WriteString(sSteam);
						g_Database.Query(SQL_SelectTeam, sQuery, pack);
					}
				}
			}
			iTimes++;
		}
	}
}

public void SQL_SelectTeam(Database db, DBResultSet results, const char[] sError, DataPack pack)
{
	if(results == null)
	{
		PrintToServer("MySQL Query Failed: %s", sError);
		LogError("MySQL Query Failed: %s", sError);
	}

	if(!results.FetchRow()) return;

	int teamCol;
	results.FieldNameToNum("team", teamCol);
	int oldTeam = results.FetchInt(teamCol);

	char sQuery[1024], sSteam[64];
	pack.Reset();
	pack.ReadString(sSteam, sizeof(sSteam));
	delete pack;

	switch(oldTeam)
	{
		case 2:
		{
			Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET team=3 WHERE steamid64='%s';", sSteam);
		}
		case 3:
		{
			Format(sQuery, sizeof(sQuery), "UPDATE ladder_stats SET team=2 WHERE steamid64='%s';", sSteam);
		}
		default:
		{
			Format(sQuery, sizeof(sQuery), "Error catching;");
		}
	}

	g_Database.Query(SQL_GenericQuery, sQuery);
}

//generic query handler
public void SQL_GenericQuery(Database db, DBResultSet results, const char[] sError, any data)
{
    if(results == null)
    {
        PrintToServer("MySQL Query Failed: %s", sError);
        LogError("MySQL Query Failed: %s", sError);
    }
}

stock bool IsValidClient(int client)
{
    return client >= 1 && 
    client <= MaxClients && 
    IsClientConnected(client) && 
    IsClientAuthorized(client) && 
    IsClientInGame(client) &&
    !IsFakeClient(client);
}

stock int GetTimestamp(int year, int month, int day)
{
	return ((year - 1970) * 31556926) + (month * 2629743) + (day * 86400);
}