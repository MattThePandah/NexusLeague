#include <sourcemod> 

#pragma semicolon 1

public OnPluginStart() 
{ 
    AddCommandListener(OnSay, "say"); 
    AddCommandListener(OnSay, "say_team"); 
} 

public Action:OnSay(client, const String:command[], args) 
{ 
    char text[4096]; 
    GetCmdArgString(text, sizeof(text)); 
    StripQuotes(text);
    if (StrEqual(text, "﷽")) {
        PrintToChat(client, "[SM] We do not allow the use of this bind.");
        return Plugin_Handled;
    } 
    if (StrEqual(text, "dathost.net")) {
        return Plugin_Handled;
    }
    return Plugin_Continue;
} 