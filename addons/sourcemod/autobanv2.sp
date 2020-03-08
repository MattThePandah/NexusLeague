#include <get5>
#include <sdktools>
#include <socket>
#include <smjansson>
#include <base64>

float g_fTeamDamage[MAXPLAYERS + 1];

Handle g_aPlayerIDs;
Handle g_aPlayerTime;
Handle g_aPlayerName;

ConVar g_hCVFallbackTime;
ConVar g_hCVServerIp;
ConVar g_hCVGracePeriod;

Database g_Database = null;

public void OnPluginStart()
{
    // Event Hooks
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);

    g_aPlayerIDs = CreateArray(64);
    g_aPlayerTime = CreateArray();
    g_aPlayerName = CreateArray(128);

    g_hCVFallbackTime = CreateConVar("sm_autoban_fallback_time", "120", "Time a player should be banned for if MySQL ban fails.");
    g_hCVServerIp = CreateConVar("sqlmatch_websocket_ip", "127.0.0.1", "IP to connect to for sending ban messages.");
    g_hCVGracePeriod = CreateConVar("sm_autoban_grace_period", "150", "The amount of time a player has to rejoin before being banned for afk/disconnect bans.");

    CreateTimer(1.0, Timer_CheckBan, _, TIMER_REPEAT);
}

public Action Timer_CheckBan(Handle timer, int userid)
{
    int size = GetArraySize(g_aPlayerTime);
    if (size == 0) return;

    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client)) return Plugin_Stop;
    
    char steam64[64];
    char name[128];

    // AFK Stuff
    for (int i = 0; i < size; i++)
    {
        if (GetTime() > GetArrayCell(g_aPlayerTime, i) + g_hCVGracePeriod.IntValue)
        {
            GetArrayString(g_aPlayerIDs, i, steam64, sizeof(steam64));
            GetArrayString(g_aPlayerName, i, name, sizeof(name));

            char sQuery[1024];
            Format(sQuery, sizeof(sQuery), "INSERT INTO bans (steamid, reason, active) VALUES ('%s', 'Automatic AFK Ban', 1);", steam64);
            g_Database.Query(SQL_InsertBan, sQuery);

        }
    }
}