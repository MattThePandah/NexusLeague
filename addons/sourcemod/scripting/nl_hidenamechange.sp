#include <sourcemod>
#include <sdktools>

#pragma semicolon 1 
#pragma newdecls required

#define NAME_CHANGE_STRING "#Cstrike_Name_Change"

bool b_HideNameChange = false;

public void OnPluginStart()
{
    HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char[] sMessage = new char[24];

    if (GetUserMessageType() == UM_Protobuf)
    {
        Protobuf pbmsg = msg;
        pbmsg.ReadString("msg_name", sMessage, 24);
    }

    else
    {
        BfRead bfmsg = msg;
        bfmsg.ReadByte();
        bfmsg.ReadByte();
        bfmsg.ReadString(sMessage, 24, false);
    }

    if (StrEqual(sMessage, NAME_CHANGE_STRING))
    {
        return Plugin_Handled;
    }
}