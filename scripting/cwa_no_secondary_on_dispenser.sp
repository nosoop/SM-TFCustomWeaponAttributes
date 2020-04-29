/**
 * Custom Weapons Attribute: No secondary ammo from dispensers while active
 * Requested by Karma Charger
 * 1k */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#include <tf2_stocks>
#include <tf_custom_attributes>
#include <stocksoup/log_server>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Weapons Attribute: No Secondary Ammo From Dispensers While Active",
	author = "nosoop",
	description = "Prevents players from getting ammo for their secondary weapon while the "
			... "current weapon is active.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes"
}

#define ATTR_NO_SEC_AMMO_FROM_DISPENSERS_WHILE_ACTIVE "no secondary ammo from dispensers while active"

Handle g_hDispenseAmmo;

// prevent ammo pickup while dispenser is providing ammo
bool g_bDisableAmmoPickup[MAXPLAYERS+1];

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cw2_no_secondary_from_dispenser");
	
	if (hGameConf == null) {
		SetFailState("Missing gamedata");
	}
	
	int offsetDispenseAmmo = GameConfGetOffset(hGameConf, "CObjectDispenser::DispenseAmmo");
	g_hDispenseAmmo = DHookCreate(offsetDispenseAmmo, HookType_Entity, ReturnType_Bool,
			ThisPointer_CBaseEntity);
	DHookAddParam(g_hDispenseAmmo, HookParamType_CBaseEntity, _, DHookPass_ByRef);
	
	// the ammo dispense functionality bypasses vtables gg
	Handle dt_PlayerGiveAmmo = DHookCreateFromConf(hGameConf,
			"CTFPlayer::GiveAmmo(EAmmoSource)");
	DHookEnableDetour(dt_PlayerGiveAmmo, false, OnPlayerReceiveAmmo);
	
	delete hGameConf;
	
	HookExistingEntities();
}

public void OnClientPutInServer(int client) {
	g_bDisableAmmoPickup[client] = false;
}

/**
 * Handle late-loaded plugin -- hook the necessary entities
 */
static void HookExistingEntities() {
	int entity = -1;
	while ( (entity = FindEntityByClassname(entity, "obj_dispenser")) != -1 ) {
		OnDispenserSpawnPost(entity);
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "obj_dispenser", false)) {
		SDKHook(entity, SDKHook_SpawnPost, OnDispenserSpawnPost);
	}
}

public void OnDispenserSpawnPost(int dispenser) {
    DHookEntity(g_hDispenseAmmo, false, dispenser, .callback = OnDispenseAmmo);
    DHookEntity(g_hDispenseAmmo, true, dispenser, .callback = OnDispenseAmmoPost);
}

/**
 * Determines if we are currently in the ammo dispense function
 */

static int s_ClientContextInDispenseAmmo;

public MRESReturn OnDispenseAmmo(int pThis, Handle hReturn, Handle hParams) {
	int client = DHookGetParam(hParams, 1);
	s_ClientContextInDispenseAmmo = GetClientSerial(client);
	return MRES_Ignored;
}

public MRESReturn OnDispenseAmmoPost(int pThis, Handle hReturn, Handle hParams) {
	s_ClientContextInDispenseAmmo = 0;
}

/**
 * Blocks receiving secondary ammo if the current active weapon has the
 * "no secondary ammo from dispensers while active" attribute.
 */
public MRESReturn OnPlayerReceiveAmmo(int client, Handle hReturn, Handle hParams) {
	if (!client || client != GetClientFromSerial(s_ClientContextInDispenseAmmo)) {
		return MRES_Ignored;
	}
	
	int hSecondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if (!IsValidEntity(hSecondaryWeapon)) {
		return MRES_Ignored;
	}
	
	// check if receiving secondary ammo
	int ammoType = DHookGetParam(hParams, 2);
	if (GetEntProp(hSecondaryWeapon, Prop_Send, "m_iPrimaryAmmoType") != ammoType
			|| CanGetSecondaryAmmoFromDispensers(client)) {
		return MRES_Ignored;
	}
	
	DHookSetReturn(hReturn, 0);
	return MRES_Supercede;
}

/**
 * Returns false if the current active weapon has the
 * "no secondary ammo from dispensers while active" attribute set.
 */
static bool CanGetSecondaryAmmoFromDispensers(int client) {
	int hActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	
	if (!IsValidEntity(hActiveWeapon)) {
		return true;
	}
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(hActiveWeapon);
	bool bIsSecondaryLimited;
	
	if (attr) {
		bIsSecondaryLimited = !!attr.GetNum(ATTR_NO_SEC_AMMO_FROM_DISPENSERS_WHILE_ACTIVE);
		delete attr;
	}
	return !bIsSecondaryLimited;
}
