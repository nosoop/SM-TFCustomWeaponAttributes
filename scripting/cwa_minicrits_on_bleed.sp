#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <tf2attributes>

#include <sdkhooks>
#include <sdktools>
#include <customweaponstf>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Minicrits on Bleed",
    author = "nosoop",
    description = "Weapon damage is minicrits if the victim is bleeding.",
    version = PLUGIN_VERSION,
    url = "localhost"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_MINICRIT_BLEED "minicrits on bleed"

ArrayList g_MinicritBleedWeapons;

public void OnPluginStart() {
	g_MinicritBleedWeapons = new ArrayList();
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnPlayerDamage);
}

public Action OnPlayerDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (damagetype & DMG_CRIT) {
		return Plugin_Continue;
	}
	
	if (TF2_IsPlayerInCondition(victim, TFCond_Bleeding)
			&& g_MinicritBleedWeapons.FindValue(weapon) != -1) {
		FakeMinicritEffect(attacker, victim);
		damage *= 1.35;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

// Creates the minicrit particle effect and displays it to the attacker with an appropriate effect.
void FakeMinicritEffect(int attacker, int victim) {
	int particles = FindStringTable("ParticleEffectNames");
	int i, count = GetStringTableNumStrings(particles);
	char buffer[16];
	for (i = 0; i < count; i++) {
		ReadStringTable(particles, i, buffer, sizeof(buffer));
		if (StrEqual(buffer, "minicrit_text", false)) {
			break;
		}
	}
	
	TE_Start("TFParticleEffect");
	float vecPos[3];
	GetClientEyePosition(victim, vecPos);
	vecPos[2] += 4.0;
	TE_WriteFloat("m_vecOrigin[0]", vecPos[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecPos[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecPos[2]);
	TE_WriteNum("m_iParticleSystemIndex", i);
	TE_WriteNum("m_bResetParticles", true);
	
	int[] clients = new int[MaxClients];
	int num;
	clients[num++] = attacker;
	TE_Send(clients, num);
	
	ClientCommand(attacker, "playgamesound TFPlayer.CritHitMini");
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_MinicritBleedWeapons.FindValue(entity)) != -1) {
		g_MinicritBleedWeapons.Erase(index);
	}
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_MINICRIT_BLEED)) {
		g_MinicritBleedWeapons.Push(weapon);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
