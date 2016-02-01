/**
 * A proof-of-concept plugin that prevents players from gaining secondary ammo from dispensers
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>

#include <sdkhooks>
#include <sdktools>

#include <dhooks>

#include <customweaponstf>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] 'No Secondary Ammo From Dispenser While Active' Attribute Test",
    author = "nosoop",
    description = "Prevents players from gaining secondary ammo from dispensers.",
    version = PLUGIN_VERSION,
    url = "localhost"
}

int m_nAmmoSecondary[MAXPLAYERS+1];
int m_nClipSecondary[MAXPLAYERS+1];

// CObjectDispenser::DispenseAmmo(CTFPlayer *pPlayer)
// See https://forums.alliedmods.net/showthread.php?t=259931
Handle g_hDispenseAmmo;

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.cw2_no_secondary_from_dispenser");
	
	if (hGameConf == null) {
		SetFailState("Missing gamedata");
	}
	
	int offsetDispenseAmmo = GameConfGetOffset(hGameConf, "CObjectDispenser::DispenseAmmo");
	PrintToServer("CObjectDispenser::DispenseAmmo vtable offset: %d", offsetDispenseAmmo);
	g_hDispenseAmmo = DHookCreate(offsetDispenseAmmo, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, CObjectDispenser_DispenseAmmo);
	DHookAddParam(g_hDispenseAmmo, HookParamType_CBaseEntity, _, DHookPass_ByRef);
	
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
    DHookEntity(g_hDispenseAmmo, false, dispenser);
}

/**
 * Hooks the dispenser's "dispense ammo" functionality.
 * Stores the current ammo count and re-applies it on the next frame.
 */
public MRESReturn CObjectDispenser_DispenseAmmo(int pThis, Handle hReturn, Handle hParams) {
	int client = DHookGetParam(hParams, 1);
	
	int hSecondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	
	m_nAmmoSecondary[client] = GetAmmo(client, hSecondaryWeapon);
	m_nClipSecondary[client] = GetEntProp(hSecondaryWeapon, Prop_Data, "m_iClip1");
	
	RequestFrame(RequestFrame_ResetSecondaryAmmo, client);
	
	return MRES_Ignored;
}

public void RequestFrame_ResetSecondaryAmmo(int client) {
	int hSecondaryWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	
	// TODO only reset ammo if lower than current count
	SetAmmo(client, hSecondaryWeapon, m_nAmmoSecondary[client]);
	SetClip(hSecondaryWeapon, m_nClipSecondary[client]);
	
	// TODO stop ammo sound if player did not gain ammo
}

// Stock from AdvancedInfiniteAmmo
stock void SetAmmo(int client, int iWeapon, int iAmmo = 500) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType != -1) {
		SetEntProp(client, Prop_Data, "m_iAmmo", iAmmo, _, iAmmoType);
	}
}

stock int GetAmmo(int client, int iWeapon) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType != -1) {
		return GetEntProp(client, Prop_Data, "m_iAmmo", _, iAmmoType);
	}
	return 0;
}

// Stock from AdvancedInfiniteAmmo
stock void SetClip(int iWeapon, int iClip = 99) {
	SetEntProp(iWeapon, Prop_Data, "m_iClip1", iClip);
}
