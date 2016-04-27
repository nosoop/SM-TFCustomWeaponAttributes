/**
 * [TF2] Custom Weapon Attribute: Blast and Sentry resistance on kill
 * 
 */
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
    name = "[TF2] Custom Weapon Attribute: Blast and Sentry Resistance On Kill",
    author = "nosoop",
    description = "Provides an amount of resistances on kill.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_RESISTANCES "on kill blast and sentry resist"

ArrayList g_ResistWeapons;

float g_flBuffEndTime[MAXPLAYERS+1];

enum ResistWeaponAttributes {
	ResistWeapon_Entity = 0,
	ResistWeapon_Percentage,
	ResistWeapon_Duration
};

public void OnPluginStart() {
	g_ResistWeapons = new ArrayList(view_as<int>(ResistWeaponAttributes));
	
	RegAdminCmd("sm_fakeresist", AdminCmd_FakeResist, ADMFLAG_ROOT);
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
}

public Action AdminCmd_FakeResist(int client, int argc) {
	TransmitOverlay(client, "");
	return Plugin_Handled;
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_RESISTANCES)) {
		int index;
		
		if ( (index = g_ResistWeapons.FindValue(weapon)) == -1)  {
			index = g_ResistWeapons.Push(weapon);
		}
		
		// default values - 50% resistance for 5 seconds
		float values[2] = { 0.5, 5.0 };
		
		StringToDuple(value, values);
		
		// clamp values to percentage scale
		values[ResistWeapon_Percentage] = values[ResistWeapon_Percentage] > 1.0 ?
				1.0 : values[ResistWeapon_Percentage];
		values[ResistWeapon_Percentage] = values[ResistWeapon_Percentage] < 0.0 ?
				0.0 : values[ResistWeapon_Percentage];
		
		for (int i = 0; i < sizeof(values); i++) {
			g_ResistWeapons.Set(index, values[i], i + 1);
		}
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

/**
 * Workaround for resistances being broken
 */
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype) {
	if (GetGameTime() > g_flBuffEndTime[victim]) {
		return Plugin_Continue;
	} else {
		Address pAttr;
		if (damagetype & DMG_BLAST
				&& victim != attacker
				&& (pAttr = TF2Attrib_GetByName(victim, "dmg taken from blast reduced"))
				!= Address_Null) {
			// we have blast reduction
			// TODO reduced damage from blast jumps?
			float flValue = TF2Attrib_GetValue(pAttr);
			
			damage *= (1.0 - flValue);
			return Plugin_Changed;
		} else if ((pAttr = TF2Attrib_GetByName(victim, "SET BONUS: dmg from sentry reduced"))
				!= Address_Null){
			// we have sentry reduction
			char entclass[32];
			GetEntityClassname(inflictor, entclass, sizeof(entclass));
			
			if (StrEqual(entclass, "obj_sentrygun")) {
				float flValue = TF2Attrib_GetValue(pAttr);
				damage *= (1.0 - flValue);
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) {
	if (!IsPlayerAlive(victim) || GetClientHealth(victim) <= 0) {
		int index;
		if ( (index = g_ResistWeapons.FindValue(weapon)) > -1) {
			// Resistance event
			TF2Attrib_SetByName(attacker, "SET BONUS: dmg from sentry reduced",
					g_ResistWeapons.Get(index, view_as<int>(ResistWeapon_Percentage)));
			TF2Attrib_SetByName(attacker, "dmg taken from blast reduced",
					g_ResistWeapons.Get(index, view_as<int>(ResistWeapon_Percentage)));
			
			float flDuration = g_ResistWeapons.Get(index, view_as<int>(ResistWeapon_Duration));
			
			g_flBuffEndTime[attacker] = GetGameTime() + flDuration;
			
			TransmitUberOverlay(attacker);
			
			DataPack dataPack;
			CreateDataTimer(flDuration, OnResistanceRemoval, dataPack, TIMER_FLAG_NO_MAPCHANGE);
			dataPack.WriteCell(GetClientUserId(attacker));
			dataPack.WriteFloat(g_flBuffEndTime[attacker]);
		}
	}
}

public Action OnResistanceRemoval(Handle timer, DataPack dataPack) {
	dataPack.Reset();
	int attackingClient = GetClientOfUserId(dataPack.ReadCell());
	float flBuffEndTime = dataPack.ReadFloat();
	
	if (attackingClient && g_flBuffEndTime[attackingClient] == flBuffEndTime) {
		// Resistance event
		TF2Attrib_RemoveByName(attackingClient, "SET BONUS: dmg from sentry reduced");
		TF2Attrib_RemoveByName(attackingClient, "dmg taken from blast reduced");
		
		TransmitOverlay(attackingClient, "");
	}
}

public void OnEntityDestroyed(int entity) {
	int index;
		
	if ( (index = g_ResistWeapons.FindValue(entity)) != -1)  {
		g_ResistWeapons.Erase(index);
	}
}

stock void TransmitUberOverlay(int client) {
	TFTeam team = TF2_GetClientTeam(client);
	
	switch (team) {
		case TFTeam_Red: {
			TransmitOverlay(client, "effects/invuln_overlay_red");
		}
		case TFTeam_Blue: {
			TransmitOverlay(client, "effects/invuln_overlay_blue");
		}
	}
}

stock void TransmitOverlay(int client, const char[] overlay) {
	ClientCommand(client, "r_screenoverlay \"%s\"", overlay);
}

/**
 * Gets the entity's target name, giving it one if it doesn't exist if possible.
 * 
 * @return True if the entity had or received a target name, false if the entity does not
 * support it.
 */
stock bool GetEntityTargetName(int entity, char[] target, int maxlen,
		const char[] prefix = "__sm_target_no_name_") {
	static int nEmptyTargets = 0;
	nEmptyTargets %= 0xFFFF;
	
	if (HasEntProp(entity, Prop_Data, "m_iName")) {
		GetEntPropString(entity, Prop_Data, "m_iName", target, maxlen);
		
		if (strlen(target) == 0) {
			Format(target, maxlen, "%s%d", prefix, nEmptyTargets++);
			SetEntPropString(entity, Prop_Data, "m_iName", target);
		}
		return true;
	}
	return false;
}