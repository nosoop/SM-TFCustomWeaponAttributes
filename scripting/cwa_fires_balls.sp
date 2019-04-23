/**
 * [TF2] Custom Weapon Attribute: Launches balls that stun opponents
 * 
 * What part of "not suitable for production use" don't people understand?
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <tf2attributes>

#include <sdkhooks>
#include <dhooks>

#pragma newdecls required

#include <stocksoup/tf/weapon>
#include <tf_custom_attributes>

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
	name = "[TF2] Custom Weapon Attribute: Fires Stunballs",
	author = "nosoop",
	description = "Launches balls that stun opponents.",
	version = PLUGIN_VERSION,
	url = "localhost"
}

#define ATTR_FIRES_STUNBALLS "override projectile stunballs"
#define MINIGUN_STUNBALL_SPEED 1100.0

Handle g_SDKCallGetProjectileFireSetup;

bool g_bWeaponDemonstration = true;

int offs_CTFStunball_flInitialLaunchTime;

public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("tf2.cwa_fires_stunballs");
	if (hGameData == INVALID_HANDLE) {
		SetFailState("Unable to load required gamedata (tf2.cwa_fires_stunballs.txt)");
	}
	
	Handle dtBaseGunFireProjectile = DHookCreateFromConf(hGameData,
			"CTFWeaponBaseGun::FireProjectile()");
	DHookEnableDetour(dtBaseGunFireProjectile, false, OnBaseGunFireProjectilePre);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual,
			"CTFWeaponBase::GetProjectileFireSetup()");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByValue);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Pointer,
			.encflags = VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_Pointer,
			.encflags = VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	g_SDKCallGetProjectileFireSetup = EndPrepSDKCall();
	
	offs_CTFStunball_flInitialLaunchTime = GameConfGetOffset(hGameData,
			"CTFStunball::m_flInitialLaunchTime");
	
	delete hGameData;
}

/**
 * Forces the stunball weapon to fire a stunball.
 */
public MRESReturn OnBaseGunFireProjectilePre(int weapon, Handle hParams) {
	if (!IsStunballWeapon(weapon)) {
		return MRES_Ignored;
	}
	
	// force projectile type override attribute so the client-side bullet visuals don't show up
	TF2Attrib_SetByName(weapon, "override projectile type", 6.0);
	
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	
	// refer to CTFWeaponBaseGun::FireRocket()
	float vecOffset[3], vecSrc[3], angForward[3];
	vecOffset[0] = 23.5;
	vecOffset[1] = 12.0;
	vecOffset[2] = -35.0;
	
	if (GetEntityFlags(owner) & FL_DUCKING) {
		vecOffset[2] += 11.0;
	}
	
	// this performs a bunch of magic to determine a projectile's "proper" spawn position
	SDKCall(g_SDKCallGetProjectileFireSetup, weapon, owner, vecOffset, vecSrc, angForward,
			false, MINIGUN_STUNBALL_SPEED);
	
	CreateStunball(owner, weapon, vecSrc, angForward);
	
	// decrement ammo count on weapon
	int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (owner > 0 && owner <= MaxClients && ammoType != -1) {
		int amount = GetEntProp(owner, Prop_Send, "m_iAmmo", 4, ammoType);
		SetEntProp(owner, Prop_Send, "m_iAmmo", amount - 1, 4, ammoType);
	}
	
	return MRES_Supercede;
}

int CreateStunball(int hOwner, int hLauncher, const float vecOrigin[3],
		const float vecAngles[3]) {
	int stunball = CreateEntityByName("tf_projectile_stun_ball");
	
	if (!IsValidEntity(stunball)) {
		return INVALID_ENT_REFERENCE;
	}
	
	// TODO use CalcIsAttackCriticalHelper
	bool bCritical = false; // GetEntProp(flare, Prop_Send, "m_bCritical") > 0;
	
	SetEntPropEnt(stunball, Prop_Data, "m_hThrower", hOwner);
	SetEntProp(stunball, Prop_Data, "m_bIsLive", true);
	
	SetEntProp(stunball, Prop_Send, "m_bCritical", bCritical);
	
	float vecVelocity[3];
	vecVelocity = vecAngles;
	
	GetAngleVectors(vecAngles, vecVelocity, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vecVelocity, MINIGUN_STUNBALL_SPEED);
	
	/**
	 * Compensate for the vertical offset with this:
	 * v = sqrt( 0.5 * gravity * height )
	 * 
	 * Thanks, physics!
	 */
	float flVerticalOffset = 35.0;
	vecVelocity[2] += SquareRoot(2 * 800 * flVerticalOffset);
	
	DispatchSpawn(stunball);
	TeleportEntity(stunball, vecOrigin, vecAngles, vecVelocity);
	
	SDKHook(stunball, SDKHook_TouchPost, OnStunballTouchPost);
	return stunball;
}

public void OnStunballTouchPost(int stunball, int other) {
	int hThrower = GetEntPropEnt(stunball, Prop_Data, "m_hThrower");
	
	if (other && other < MaxClients && IsPlayerAlive(other)) {
		if (GetEntProp(stunball, Prop_Data, "m_bIsLive")
				&& TF2_GetClientTeam(hThrower) != TF2_GetClientTeam(other)) {
			// Stun player
			OnStunballHit(stunball, other);
		} else if (other == hThrower) {
			// avoid picking up balls that were just launched
			float flSpawnTime = GetEntDataFloat(stunball, offs_CTFStunball_flInitialLaunchTime);
			if (GetGameTime() - flSpawnTime > 0.2 && RefillStunballCustom(other)) {
				RemoveEntity(stunball);
			}
		}
		
		SetVariantString("ParticleEffectStop");
		AcceptEntityInput(stunball, "DispatchEffect");
	}
	
	// TODO make sure that the object we are colliding with is not an invisible brush
	SetEntProp(stunball, Prop_Data, "m_bIsLive", false);
	
	// It touched a thing, so kill it after a second.
	if (!g_bWeaponDemonstration) {
		CreateTimer(1.0, Timer_DespawnBall, EntIndexToEntRef(stunball));
		AcceptEntityInput(stunball, "Kill");
	}
}

void OnStunballHit(int stunball, int victim) {
	int hThrower = GetEntPropEnt(stunball, Prop_Data, "m_hThrower");
	
	int damageFlags = DMG_CLUB;
	
	bool bCritical = GetEntProp(stunball, Prop_Send, "m_bCritical") > 0;
	
	if (bCritical) {
		damageFlags |= DMG_CRIT;
	}
	
	// Headshot detection
	// ...-ish.  It's not perfect, but it'll do.
	// Ideally we can traceattack to determine exactly what we hit, but too lazy.
	float vecStunballOrigin[3], vecVictimEyePosition[3];
	GetEntPropVector(stunball, Prop_Data, "m_vecOrigin", vecStunballOrigin);
	GetClientEyePosition(victim, vecVictimEyePosition);
	
	float flDistanceToFace = GetVectorDistance(vecStunballOrigin, vecVictimEyePosition);
	if (flDistanceToFace < 30.0) {
		TF2_StunPlayer(victim, 1.0, _, TF_STUNFLAGS_SMALLBONK, hThrower);
		SDKHooks_TakeDamage(victim, stunball, hThrower, 20.0, damageFlags, -1);
	} else {
		SDKHooks_TakeDamage(victim, stunball, hThrower, 15.0, damageFlags, -1);
	}
}

public Action Timer_DespawnBall(Handle timer, int entref) {
	int stunball = EntRefToEntIndex(entref);
	
	if (IsValidEntity(stunball)) {
		AcceptEntityInput(stunball, "Kill");
	}
}

bool IsStunballWeapon(int weapon) {
	if (!IsValidEntity(weapon)) {
		return false;
	}
	
	KeyValues attr = TF2CustAttr_GetAttributeKeyValues(weapon);
	bool bIsStunballWeapon;
	
	if (attr) {
		bIsStunballWeapon = !!attr.GetNum(ATTR_FIRES_STUNBALLS);
		delete attr;
	}
	return bIsStunballWeapon;
}

/**
 * Returns true if a stunball-shooting weapon was refilled.
 */
bool RefillStunballCustom(int client) {
	int slot = TFWeaponSlot_Primary;
	int weapon = -1;
	while (IsValidEntity((weapon = GetPlayerWeaponSlot(client, slot++)))) {
		if (IsStunballWeapon(weapon) && TF2_GiveWeaponAmmo(weapon, 1, false)) {
			return true;
		}
	}
	return false;
}
