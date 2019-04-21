/**
 * Custom Weapons Attribute: Exploding Sapper
 * Requested by Karma Charger
 * 5k */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <tf2_morestocks>

#include <tf_custom_attributes>

#include <stocksoup/datapack>
#include <stocksoup/tf/hud_notify>

#include <stocksoup/log_server>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Exploding Sapper",
    author = "nosoop",
    description = "Sapper goes boom.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/tree/custattr-conv"
}

#define PARTICLE_NAME_LENGTH 32

// attributes format `${key}=${value}` pairs, space delimited
// valid keys include `damage`, `radius`, `sap_time`, `disable_time`, `particle`, and `sound`
#define ATTR_EXPLODING_SAPPER "exploding sapper"

// I can't be bothered to pick an appropriate particle effect
#define SAPPER_DEFAULT_EXPLODING_EFFECT "ghost_appearation"

float g_flClientSapLockTime[MAXPLAYERS+1];

bool g_bSpewGarbage = false;

Handle g_SDKCallWeaponSwitch;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("sdkhooks.games");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (sdkhooks.games).");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallWeaponSwitch = EndPrepSDKCall();
	if (!g_SDKCallWeaponSwitch) {
		SetFailState("Could not initialize call for CTFPlayer::Weapon_Switch");
	}
	
	delete hGameConf;
	
	HookEvent("player_sapped_object", OnObjectSapped);
	HookEvent("post_inventory_application", OnPlayerLoadoutRefresh);
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_flClientSapLockTime[client] = 0.0;
	
	// TODO fully prevent client from switching weapon
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnSapperSwitch);
}

public void OnPlayerLoadoutRefresh(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_flClientSapLockTime[client] = 0.0;
}

public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int buildingtype = event.GetInt("object");
	int sapperobj = event.GetInt("sapperid");
	
	char classname[64];
	GetEntityClassname(sapperobj, classname, sizeof(classname));
	
	int building = GetEntPropEnt(sapperobj, Prop_Data, "m_hParent");
	
	DebugToServer("building %d (type %d) being sapped by sapper %d (%s) from player %N",
			building, buildingtype, sapperobj, classname, attacker);
	
	// the sapperobj is the entity attached to the building, not the weapon itself
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(sapper);
	if (!attr) {
		DebugToServer("sapper has no custom attributes");
		return;
	}
	
	char explodingSapperProps[512];
	attr.GetString(ATTR_EXPLODING_SAPPER, explodingSapperProps, sizeof(explodingSapperProps));
	delete attr;
	
	if (!explodingSapperProps[0]) {
		// not an exploding sapper
		DebugToServer("not an exploding sapper");
		return;
	}
	
	DebugToServer("is an exploding sapper");
	
	float flSapperDamage = ReadFloatVar(explodingSapperProps, "damage", 216.0);
	float flSapperRadius = ReadFloatVar(explodingSapperProps, "radius", 300.0);
	float flSapperTime = ReadFloatVar(explodingSapperProps, "sap_time", 5.0);
	float flSapperDisableTime = ReadFloatVar(explodingSapperProps, "disable_time", 2.0);
	
	char sapperExplodeParticle[PARTICLE_NAME_LENGTH], sapperExplodeSound[PLATFORM_MAX_PATH];
	ReadStringVar(explodingSapperProps, "particle", sapperExplodeParticle,
			sizeof(sapperExplodeParticle), "ghost_appearation");
	ReadStringVar(explodingSapperProps, "sound", sapperExplodeSound, sizeof(sapperExplodeSound),
			"");
	
	DebugToServer("Sapper info: damage %f, radius %f, particle %s, time %f",
			flSapperDamage, flSapperRadius, sapperExplodeParticle, flSapperTime);
	DebugToServer("... sound %s", sapperExplodeSound);
	
	DataPack sapperData;
	CreateDataTimer(flSapperTime, OnSapperExplode, sapperData);
	
	WritePackClient(sapperData, attacker);
	WritePackEntity(sapperData, sapperobj);
	
	sapperData.WriteFloat(flSapperDamage);
	sapperData.WriteFloat(flSapperRadius);
	
	sapperData.WriteString(sapperExplodeParticle);
	sapperData.WriteString(sapperExplodeSound);
	
	ForceSwitchFromSecondaryWeapon(attacker);
	SetSapperCooldownTimer(attacker, flSapperDisableTime);
}

public Action OnSapperExplode(Handle timer, DataPack sapperData) {
	sapperData.Reset();
	
	char sapperExplodeParticle[PARTICLE_NAME_LENGTH];
	char sapperExplodeSound[PLATFORM_MAX_PATH];
	
	int attacker = ReadPackClient(sapperData);
	int sapperobj = ReadPackEntity(sapperData);
	
	// attacker left or sapper doesn't exist anymore
	if (!attacker || !IsValidEntity(sapperobj)) {
		return Plugin_Handled;
	}
	
	float flSapperDamage = sapperData.ReadFloat();
	float flSapperRadius = sapperData.ReadFloat();
	sapperData.ReadString(sapperExplodeParticle, sizeof(sapperExplodeParticle));
	sapperData.ReadString(sapperExplodeSound, sizeof(sapperExplodeSound));
	
	DebugToServer("Sapper info: damage %f, radius %f, particle %s",
			flSapperDamage, flSapperRadius, sapperExplodeParticle);
	
	int building = GetEntPropEnt(sapperobj, Prop_Data, "m_hParent");
	
	float vecOrigin[3];
	GetEntPropVector(building, Prop_Data, "m_vecOrigin", vecOrigin);
	
	int bomb = TF2_CreateGenericBomb(vecOrigin, flSapperDamage, flSapperRadius,
			sapperExplodeParticle, sapperExplodeSound);
	SDKHooks_TakeDamage(bomb, attacker, attacker, 5.0);
	AcceptEntityInput(bomb, "Detonate");
	AcceptEntityInput(bomb, "Kill");
	
	DebugToServer("Sapper exploded?");
	
	if (IsValidEntity(sapperobj)) {
		AcceptEntityInput(sapperobj, "Kill");
	}
	return Plugin_Handled;
}

stock int TF2_CreateGenericBomb(float vecOrigin[3], float flDamage = 0.0, float flRadius = 0.0,
		const char[] strParticle = "", const char[] strSound = "") {
	int iBomb = CreateEntityByName("tf_generic_bomb");
	DispatchKeyValueVector(iBomb, "origin", vecOrigin);
	DispatchKeyValueFloat(iBomb, "damage", flDamage);
	DispatchKeyValueFloat(iBomb, "radius", flRadius);
	DispatchKeyValue(iBomb, "health", "1");
	
	if (strlen(strParticle) > 0) {
		DispatchKeyValue(iBomb, "explode_particle", strParticle);
	}
	
	if (strlen(strSound) > 0) {
		DispatchKeyValue(iBomb, "sound", strSound);
	}
	
	char netclass[32];
	GetEntityNetClass(iBomb, netclass, sizeof(netclass));
	DebugToServer("bomb entity %s", netclass);
	
	DispatchSpawn(iBomb);
	return iBomb;
}  

void ForceSwitchFromSecondaryWeapon(int client) {
	int weapon = INVALID_ENT_REFERENCE;
	if (IsValidEntity((weapon = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Melee))))
			|| IsValidEntity((weapon = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Primary))))) {
		SetActiveWeapon(client, weapon);
	}
}

public Action OnSapperSwitch(int client, int weapon) {
	if (weapon == GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper))
			&& g_flClientSapLockTime[client] > GetGameTime()) {
		EmitGameSoundToClient(client, "Player.DenyWeaponSelection");
		
		TF_HudNotifyCustom(client, "obj_status_sapper", TF2_GetClientTeam(client),
				"Sapper is disabled for another %d seconds.",
				RoundToCeil(g_flClientSapLockTime[client] - GetGameTime()));
		
		// Alternatively we can just allow the weapon switch but also prevent attack 
		SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", g_flClientSapLockTime[client]);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void SetSapperCooldownTimer(int client, float cooldown) {
	float regenTime = GetGameTime() + cooldown;
	
	int sapper = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper));
	SetEntPropFloat(sapper, Prop_Send, "m_flEffectBarRegenTime", regenTime);
	g_flClientSapLockTime[client] = regenTime;
	
	DataPack pack;
	CreateDataTimer(cooldown, OnSapperCooldownEnd, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(regenTime);
}

public Action OnSapperCooldownEnd(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	float regenTime = pack.ReadFloat();
	
	if (g_flClientSapLockTime[client] == regenTime && IsPlayerAlive(client)) {
		EmitGameSoundToClient(client, "TFPlayer.ReCharged");
	}
	return Plugin_Handled;
}

void DebugToServer(const char[] fmt, any ...) {
	if (g_bSpewGarbage) {
		char buffer[256];
		VFormat(buffer, sizeof(buffer), fmt, 2);
		LogServer("%s", buffer);
	}
}

void SetActiveWeapon(int client, int weapon) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(hActiveWeapon)) {
		bool bResetParity = !!GetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity");
		SetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity", !bResetParity);
	}
	
	SDKCall(g_SDKCallWeaponSwitch, client, weapon, 0);
}

/* handlers to read key=val space-delimited entries */

stock float ReadFloatVar(const char[] varset, const char[] key, float flDefaultValue = 0.0) {
	int iValPos = FindKeyAssignInString(varset, key);
	if (iValPos == -1) {
		return flDefaultValue;
	}
	
	float retVal;
	if (StringToFloatEx(varset[iValPos], retVal)) {
		return retVal;
	}
	return flDefaultValue;
}


stock int ReadIntVar(const char[] varset, const char[] key, int iDefaultValue = 0) {
	int iValPos = FindKeyAssignInString(varset, key);
	if (iValPos == -1) {
		return iDefaultValue;
	}
	
	int retVal;
	if (StringToIntEx(varset[iValPos], retVal)) {
		return retVal;
	}
	return iDefaultValue;
}

stock bool ReadStringVar(const char[] varset, const char[] key, char[] buffer, int maxlen,
		const char[] defVal = "") {
	int iValPos = FindKeyAssignInString(varset, key);
	if (iValPos == -1) {
		strcopy(buffer, maxlen, defVal);
		return false;
	}
	
	strcopy(buffer, maxlen, varset[iValPos]);
	int space;
	if ((space = FindCharInString(buffer, ' ')) != -1) {
		buffer[space] = '\0';
	}
	return true;
}

static stock int FindKeyAssignInString(const char[] str, const char[] key) {
	char keyBuf[32];
	strcopy(keyBuf, sizeof(keyBuf), key);
	StrCat(keyBuf, sizeof(keyBuf), "=");
	
	int iValPos = StrContains(str, keyBuf);
	if (iValPos == -1) {
		return -1;
	}
	return iValPos + strlen(keyBuf);
}
