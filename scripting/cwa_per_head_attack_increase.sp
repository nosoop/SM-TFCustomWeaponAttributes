/**
 * [TF2] Custom Weapon Attribute: Per head attack increase
 * 
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <tf2attributes>

#include <sdkhooks>
#include <sdktools>
#include <customweaponstf>

// #include <stocksoup/log_server>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Per Head Attack Increase",
    author = "nosoop",
    description = "Increases firing speed for each decapitation.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_RESISTANCES "per head attack increase"

ArrayList g_SwordWeapons;

enum SwordAttributes {
	Sword_Entity = 0,
	Sword_SpeedPerDecapita,
	Sword_MaximumSpeed,
};

float g_flModNextAttack[MAXPLAYERS+1];
float g_flModAttackSpeed[MAXPLAYERS+1];
int g_nDecapitations[MAXPLAYERS+1];
int g_nBaseHealth[MAXPLAYERS+1];

public void OnPluginStart() {
	g_SwordWeapons = new ArrayList(view_as<int>(SwordAttributes));
	
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

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_RESISTANCES)) {
		int index;
		
		if ( (index = g_SwordWeapons.FindValue(weapon)) == -1)  {
			index = g_SwordWeapons.Push(weapon);
		}
		
		// default values - 20% extra attack speed for each head up to a 100% increase
		float values[2] = { 0.2, 1.0 };
		
		StringToDuple(value, values);
		
		// clamp values to percentage scale
		values[Sword_SpeedPerDecapita - 1] = values[Sword_SpeedPerDecapita - 1] < 0.0 ?
				0.0 : values[Sword_SpeedPerDecapita - 1];
		values[Sword_MaximumSpeed - 1] = values[Sword_MaximumSpeed - 1] < 0.0 ?
				0.0 : values[Sword_MaximumSpeed - 1];
		
		for (int i = 0; i < sizeof(values); i++) {
			g_SwordWeapons.Set(index, values[i], i + 1);
		}
		LogServer("Added sword %d (mod +%f, max +%f)", weapon, GetSpeedPerHead(index),
				GetMaxAttackSpeed(index));
		LogServer("Expected values sword %d (mod +%f, max +%f)", weapon, values[0],
				values[1]);
		
		// I'm not at all fond of how CW2 works.  That's no secret.
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

bool StringToDuple(const char[] str, float vec[2]) {
	char substr[2][16];
	int count = ExplodeString(str, " ", substr, sizeof(substr), sizeof(substr[]));
	
	for (int i = 0; i < count; i++) {
		vec[i] = StringToFloat(substr[i]);
	}
	return count > 0;
}

public void OnEntityDestroyed(int entity) {
	int index;
		
	if ( (index = g_SwordWeapons.FindValue(entity)) != -1)  {
		g_SwordWeapons.Erase(index);
	}
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
	
	int index;
	if ((index = g_SwordWeapons.FindValue(hActiveWeapon)) != -1) {
		// check head count and mod rate of fire here
		g_nDecapitations[attacker]++;
		
		// SetEntProp(attacker, Prop_Send, "m_iDecapitations", g_nDecapitations[attacker]);
		
		// there's no way to work around health modification when "decapitate type" is set,
		// so don't use "decapitate type" to show a head counter.
		
		int nDecapitations = g_nDecapitations[attacker];
		
		float flSpeedPerHead = GetSpeedPerHead(index);
		float flMaxSpeed = GetMaxAttackSpeed(index);
		
		float flModAttackSpeed = nDecapitations * flSpeedPerHead;
		if (flModAttackSpeed > flMaxSpeed) {
			flModAttackSpeed = flMaxSpeed;
		}
		
		g_flModAttackSpeed[attacker] = flModAttackSpeed;
		
		LogServer("Sword modifier updated to %f (speedper: %f, max: %f, decaps: %d)",
				g_flModAttackSpeed[attacker], flSpeedPerHead, flMaxSpeed, nDecapitations);
	}
}

float GetSpeedPerHead(int index) {
	return g_SwordWeapons.Get(index, view_as<int>(Sword_SpeedPerDecapita));
}

float GetMaxAttackSpeed(int index) {
	return g_SwordWeapons.Get(index, view_as<int>(Sword_MaximumSpeed));
}

public void OnPlayerThinkPost(int client) {
	if (g_flModAttackSpeed[client] > 0.0 && IsPlayerAlive(client)) {
		int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		// we only really care about the weapon with attributes here
		if (g_SwordWeapons.FindValue(hActiveWeapon) != -1) {
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
}

void ResetSwordSpeedModifier(int client) {
	g_flModNextAttack[client] = 0.0;
	g_flModAttackSpeed[client] = 0.0;
	g_nDecapitations[client] = 0;
}

#if !defined LOG_SERVER_DEFINED
// stub for stocksoup's server-logging function
void LogServer(const char[] format, any ...) {
	// do absolutely nothing
}
#endif
