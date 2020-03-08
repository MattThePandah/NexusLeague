#pragma semicolon 1

#include <sourcemod>

public Plugin myinfo = {
	name = "Steam64 Kick Plugin",
	author = "PandahChan",
	description = "Kicks players with a steam64 id.",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart() 
{
    RegAdminCmd("sm_64kick", Command_Kick, ADMFLAG_KICK, "sm_64kick <steamid64> [reason]");
}

public Action Command_Kick(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[SM] Usage: sm_64kick <steamid64> [reason]");
        return Plugin_Handled;
    } 

    char Arguments[256];
    GetCmdArgString(Arguments, sizeof(Arguments));

    char arg[65];
    int len = BreakString(Arguments, arg, sizeof(arg));

    if (len == -1)
    {
        len = 0;
        Arguments[0] = '\0';
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            char SteamID64[512];
            GetClientAuthId(i, AuthId_SteamID64, SteamID64, sizeof(SteamID64));

            if (strcmp(arg, SteamID64, true) == 0)
            {
                char reason[64];
		        Format(reason, sizeof(reason), Arguments[len]);

                KickClient(i, reason);
            }
        }
    }
}
 