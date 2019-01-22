/**
 * [TF2] Custom Weapon Attribute: Per head attack increase
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <sdkhooks>

#include <dhooks>

#pragma newdecls required

#include <stocksoup/log_server>
#include <tf_custom_attributes>

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Per Head Attack Increase",
    author = "nosoop",
    description = "Increases firing speed for each decapitation.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/"
}

// format: `${increase_per_head}f ${maximum_attack_increase}f`
#define ATTR_DECAP_MOD "per head attack increase"

float g_flModNextAttack[MAXPLAYERS+1];
float g_flModAttackSpeed[MAXPLAYERS+1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cwa_per_head_attack_increase");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cwa_per_head_attack_increase).");
	}
	
	// You can use vtable hooks if you want, I'm just too lazy to set it up
	Handle dtSwordHealthMod = DHookCreateFromConf(hGameConf, "CTFSword::GetSwordHealthMod()");
	Handle dtSwordSpeedMod = DHookCreateFromConf(hGameConf, "CTFSword::GetSwordSpeedMod()");
	
	DHookEnableDetour(dtSwordHealthMod, true, GetSwordHealthMod);
	DHookEnableDetour(dtSwordSpeedMod, true, GetSwordSpeedMod);
	
	delete hGameConf;
	
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			SDKHook(i, SDKHook_PostThink, OnPlayerThinkPost);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThink, OnPlayerThinkPost);
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client) {
		ResetSwordSpeedModifier(client);
	}
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	
	if (victim) {
		ResetSwordSpeedModifier(victim);
	}
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if (!attacker) {
		return;
	}
	
	int hActiveWeapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(hActiveWeapon);
	if (!attr) {
		return;
	}
	
	char attrValue[128];
	attr.GetString(ATTR_DECAP_MOD, attrValue, sizeof(attrValue));
	delete attr;
	
	if (!attrValue[0]) {
		return;
	}
	
	int nDecapitations = GetEntProp(attacker, Prop_Send, "m_iDecapitations");
	
	int bufferpos;
	float flSpeedPerHead, flMaxSpeed;
	bufferpos  = StringToFloatEx(attrValue, flSpeedPerHead);
	bufferpos += StringToFloatEx(attrValue[bufferpos + 1], flMaxSpeed);
	
	float flModAttackSpeed = nDecapitations * flSpeedPerHead;
	if (flModAttackSpeed > flMaxSpeed) {
		flModAttackSpeed = flMaxSpeed;
	}
	
	g_flModAttackSpeed[attacker] = flModAttackSpeed;
	
	LogServer("Sword modifier updated to %f (speedper: %f, max: %f, decaps: %d)",
			g_flModAttackSpeed[attacker], flSpeedPerHead, flMaxSpeed, nDecapitations);
}

public void OnPlayerThinkPost(int client) {
	if (g_flModAttackSpeed[client] > 0.0 && IsPlayerAlive(client)) {
		int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		if (!IsUsingCustomDecapitationMode(hActiveWeapon)) {
			return;
		}
		
		// we only really care about the weapon with attributes here
		float flNextAttack = GetEntPropFloat(hActiveWeapon, Prop_Data,
				"m_flNextPrimaryAttack");
		
		if (g_flModNextAttack[client] < flNextAttack) {
			float flModifier = 1.0 + g_flModAttackSpeed[client];
			
			float duration = flNextAttack - GetGameTime();
			float flModNextAttack = GetGameTime()
					+ (duration / flModifier);
			
			SetEntPropFloat(hActiveWeapon, Prop_Data, "m_flNextPrimaryAttack", flModNextAttack);
			
			g_flModNextAttack[client] = flModNextAttack;
			
			SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", flModifier);
			
			LogServer("Sword modifier set to %f (mod nextattack %f -> %f)",
					flModifier, flNextAttack, g_flModNextAttack[client]);
		}
	}
}

void ResetSwordSpeedModifier(int client) {
	g_flModNextAttack[client] = 0.0;
	g_flModAttackSpeed[client] = 0.0;
}

bool IsUsingCustomDecapitationMode(int weapon) {
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(weapon);
	if (!attr) {
		return false;
	}
	
	char attrValue[128];
	attr.GetString(ATTR_DECAP_MOD, attrValue, sizeof(attrValue));
	delete attr;
	
	return attrValue[0];
}

/**
 * Speed modifier is a factor relative to current speed.
 */
public MRESReturn GetSwordSpeedMod(int sword, Handle hReturn) {
	if (IsUsingCustomDecapitationMode(sword)) {
		DHookSetReturn(hReturn, 1.0);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

/**
 * Health modifier is an additive value.
 */
public MRESReturn GetSwordHealthMod(int sword, Handle hReturn) {
	if (IsUsingCustomDecapitationMode(sword)) {
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}
