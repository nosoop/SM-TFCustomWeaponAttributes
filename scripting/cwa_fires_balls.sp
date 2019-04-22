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

#define DEGREES_PER_RADIAN 57.29577

Handle g_SDKCallBaseGunFireFlare;

bool g_bWeaponDemonstration = true;

public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("tf2.cwa_fires_stunballs");
	if (hGameData == INVALID_HANDLE) {
		SetFailState("Unable to load required gamedata (tf2.cwa_fires_stunballs.txt)");
	}
	
	Handle dtBaseGunFireProjectile = DHookCreateFromConf(hGameData,
			"CTFWeaponBaseGun::FireProjectile()");
	DHookEnableDetour(dtBaseGunFireProjectile, false, OnBaseGunFireProjectilePre);
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTFWeaponBaseGun::FireFlare()");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	
	g_SDKCallBaseGunFireFlare = EndPrepSDKCall();
	
	delete hGameData;
}

/**
 * Force the stunball weapon to fire a flare that will be replaced shortly
 * This is a temporary holdover from when this was a weapon demonstration; might fix it up
 * someday if I feel like it (or if I get paid enough, I guess).
 */
public MRESReturn OnBaseGunFireProjectilePre(int weapon, Handle hParams) {
	if (!IsStunballWeapon(weapon)) {
		return MRES_Ignored;
	}
	
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	SDKCall(g_SDKCallBaseGunFireFlare, weapon, owner);
	
	// decrement ammo count on weapon
	int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (owner > 0 && owner <= MaxClients && ammoType != -1) {
		int amount = GetEntProp(owner, Prop_Send, "m_iAmmo", 4, ammoType);
		SetEntProp(owner, Prop_Send, "m_iAmmo", amount - 1, 4, ammoType);
	}
	
	return MRES_Supercede;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_projectile_flare")) {
		// It's too early to get the spawn position when hooking spawn, so Think will have to do
		SDKHook(entity, SDKHook_Think, OnFlareSpawned);
	}
}

public void OnFlareSpawned(int flare) {
	// Gets the weapon associated with the flare.
	int hLauncher = GetEntPropEnt(flare, Prop_Send, "m_hLauncher");
	
	if (IsStunballWeapon(hLauncher)) {
		/**
		 * BUG:  Because we have to wait until the flare exists so we can get the proper angles,
		 * it may already be in a position where it can burn a player.
		 * 
		 * Basically, just don't be too close to a player.
		 * (We could possibly simulate the angles, but that sounds like a pain.)
		 */
		CreateStunballFromFlare(flare);
	}
}

int CreateStunballFromFlare(int flare) {
	int stunball = CreateEntityByName("tf_projectile_stun_ball");
	
	if (!IsValidEntity(stunball)) {
		return INVALID_ENT_REFERENCE;
	}
	
	int hLauncher = GetEntPropEnt(flare, Prop_Send, "m_hLauncher");
	int hOwner = GetEntPropEnt(hLauncher, Prop_Data, "m_hOwner");
	
	bool bCritical = GetEntProp(flare, Prop_Send, "m_bCritical") > 0;
	
	SetEntPropEnt(stunball, Prop_Data, "m_hThrower", hOwner);
	SetEntProp(stunball, Prop_Data, "m_bIsLive", true);
	
	SetEntProp(stunball, Prop_Send, "m_bCritical", bCritical);
	
	float vecVelocity[3], vecOrigin[3];
	GetEntPropVector(flare, Prop_Data, "m_vecVelocity", vecVelocity);
	GetEntPropVector(flare, Prop_Data, "m_vecOrigin", vecOrigin);
	
	float vecPlayerEyePosition[3], vecEyeWeaponOffset[3];
	
	// Minigun firing offset
	// --- This is meant for the Weapon Demonstration video firing offset to look nice.
	GetClientEyePosition(hOwner, vecPlayerEyePosition);
	
	// Get a line vector from the eye's position to the stunball origin
	MakeVectorFromPoints(vecPlayerEyePosition, vecOrigin, vecEyeWeaponOffset);
	
	// Get the angle from the eye to the stunball origin
	float vecEyeWeaponAngle[3];
	GetVectorAngles(vecEyeWeaponOffset, vecEyeWeaponAngle);
	
	// Shift to the left by ~4 degrees
	vecEyeWeaponAngle[1] += 4.0;
	
	// Get and store the forward vector of the angle as the new offset
	float vecNewEyeWeaponOffset[3];
	GetAngleVectors(vecEyeWeaponAngle, vecNewEyeWeaponOffset, NULL_VECTOR, NULL_VECTOR);
	
	// Scale the unit vector to match the old length
	ScaleVector(vecNewEyeWeaponOffset, GetVectorLength(vecEyeWeaponOffset, false));
	
	// Add the relative offset back to the eye position and save
	AddVectors(vecPlayerEyePosition, vecNewEyeWeaponOffset, vecOrigin);
	// --- end weapon demonstration offset stuff
	
	// This is for the ball to spawn closer to what you'd expect (instead of at eye-level)
	static float flVerticalOffset = 35.0;
	vecOrigin[2] -= flVerticalOffset;
	
	AcceptEntityInput(flare, "Kill");
	
	/**
	 * Compensate for the vertical offset with this:
	 * v = sqrt( 0.5 * gravity * height )
	 * 
	 * Thanks, physics!
	 */
	vecVelocity[2] += SquareRoot(2 * 800 * flVerticalOffset);
	
	DispatchSpawn(stunball);
	TeleportEntity(stunball, vecOrigin, NULL_VECTOR, vecVelocity);
	
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
			int slot = TFWeaponSlot_Primary;
			int weapon = -1;
			while (IsValidEntity((weapon = GetPlayerWeaponSlot(hThrower, slot++)))) {
				if (IsStunballWeapon(weapon) && TF2_GiveWeaponAmmo(weapon, 1, false)) {
					AcceptEntityInput(stunball, "Kill");
					break;
				}
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
