#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <sdkhooks>

/**
 * oh look, another convoluted API to deal with
 * honestly if you could just give me something like
 * 
 *     forward CW_OnCustomAttributesApplied(int entity); // so we know when attributes are loaded, only use it on entities with stuff
 *     bool CW_HasAttribute(int entity, const char[] attrib); // so we can check if an attribute is applied and hook things as required
 *     any CW_GetAttributeValue(int entity, const char[] attribute); // so we can get the value
 * 
 * that'd be all I ever really wanted
 * I think I'll just make an "attributables" plugin and an adapter for this
 */
#include <cw3-attributes>

#include <tf2attributes>

#include <stocksoup/tf/hud_notify>
#include <stocksoup/log_server>
#include <stocksoup/value_remap>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute:  Re-assault Cannon",
    author = "nosoop",
    description = "Weapon attributes that modify spinup and firing speed.",
    version = PLUGIN_VERSION,
    url = "localhost"
}

#define CW3_PLUGIN_NAME "custom-weapon-soup3"
#define ATTR_IS_REASSAULT_CANNON "is reassault cannon"

#define TF_DMG_BLEED	(DMG_SLASH)
#define TF_DMG_BULLET	(DMG_BULLET | DMG_BUCKSHOT)
#define TF_DMG_MELEE	(DMG_CLUB)

ArrayList g_AppliedWeapons;

float g_flModAttackSpeed[MAXPLAYERS+1];
float g_flLastThinkTime[MAXPLAYERS+1];

public void OnPluginStart() {
	g_AppliedWeapons = new ArrayList();
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public Action CW3_OnAddAttribute(int slot, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW3_PLUGIN_NAME, false)
			&& StrEqual(attrib, ATTR_IS_REASSAULT_CANNON)) {
		int weapon = GetPlayerWeaponSlot(client, slot);
		
		// we only use this for the meter
		TF2Attrib_SetByName(weapon, "generate rage on damage", 1.0);
		
		g_AppliedWeapons.Push(weapon);
		
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThink, OnPlayerThinkPost);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnPlayerDamagedPost);
}

public void OnPlayerThinkPost(int client) {
	if (IsPlayerAlive(client)) {
		int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		
		// we only really care about the weapon with attributes here
		if (g_AppliedWeapons.FindValue(hActiveWeapon) != -1) {
			if (g_flModAttackSpeed[client] > 0.0) {
				ModFireRate(hActiveWeapon, g_flModAttackSpeed[client] + 1.0);
			}
			
			float flWindup = GetSpinupScalarByHealth(client);
			
			ModSpinUpRate(hActiveWeapon, flWindup);
			
			/* TF_HudNotifyCustom(client, "ico_notify_flag_dropped", TF2_GetClientTeam(client),
					"internal fire rate: %.2f pct.\nwindup rate: %.2f pct.",
					(1.0 + g_flModAttackSpeed[client]) * 100.0, flWindup); */
			
			
			// rage meter caps at 100.0
			SetEntPropFloat(client, Prop_Send, "m_flRageMeter",
					100.0 * (g_flModAttackSpeed[client] / 0.5));
		}
	}
	
	// 5% / second decay -- we decrease it based on time since last decay
	float flTime = GetGameTime();
	if (g_flModAttackSpeed[client] > 0.0) {
		float delta = flTime - g_flLastThinkTime[client];
		
		g_flModAttackSpeed[client] -= delta * 0.05;
		
		if (g_flModAttackSpeed[client] < 0.0) {
			g_flModAttackSpeed[client] = 0.0;
		}
	}
	g_flLastThinkTime[client] = flTime;
}

public void OnPlayerDamagedPost(int victim, int attacker, int inflictor, float damage,
		int damagetype) {
	if (damage == 0.0 || TF2_IsPlayerInCondition(victim, TFCond_Ubercharged)) {
		return;
	}
	
	if (damagetype & DMG_BLAST) {
		// blast damage
		g_flModAttackSpeed[victim] += 0.20;
	} else if (damagetype & TF_DMG_BULLET) {
		// bullet damage? apparently it can also be buckshot
		g_flModAttackSpeed[victim] += 0.07;
	} else if (damagetype & TF_DMG_MELEE) {
		// melee damage
		g_flModAttackSpeed[victim] += 0.15;
	} else if (damagetype & (DMG_BURN | TF_DMG_BLEED)) { // DMG_SLASH is bleed
		// fire, bleed
		g_flModAttackSpeed[victim] += 0.02;
	}
	
	// cap firing speed increase at +50%
	if (g_flModAttackSpeed[victim] > 0.50) {
		g_flModAttackSpeed[victim] = 0.50;
	}
}

public void OnEntityDestroyed(int entity) {
	int index = g_AppliedWeapons.FindValue(entity);
	if (index != -1) {
		g_AppliedWeapons.Erase(index);
	}
}

void ModFireRate(int weapon, float flScale = 1.0) {
	TF2Attrib_SetByName(weapon, "fire rate bonus HIDDEN", 1.0 / flScale);
}

float GetSpinupScalarByHealth(int client) {
	// spinup time decreases linearly as health decreases, up to x0.75 time at 1/3 health
	// (e.g., about 75% at 100 health, 76% at 108, 77% at 116, &c.)
	float healthBounds[2];
	healthBounds[0] = float(TF2_GetPlayerMaxHealth(client));
	healthBounds[1] = 0.33 * TF2_GetPlayerMaxHealth(client);
	
	float spinupBounds[] = { 1.0, 0.75 };
	
	// maps to 300 (1.0) -> 100 (0.75)
	return RemapValueFloat(healthBounds, spinupBounds, float(GetClientHealth(client)), true);
}

void ModSpinUpRate(int weapon, float flScale = 1.0) {
	TF2Attrib_SetByName(weapon, "minigun spinup time decreased", flScale);
}

stock int TF2_GetPlayerMaxHealth(int client) {
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}