# SM-TFCustomWeaponAttributes
A collection of attributes for the TF2 Custom Weapons plugin.

I don't run a Custom Weapons server myself (they were commissioned), so consider these unmaintained and provided without warranty (and for educational purposes).  If you'd like to tweak them yourself and submit pull requests back upstream, that'd be awesome!

The plugins prefixed with `cwa_` are tested against Custom Weapons 2 (beta 6); no guarantees they will work in any future (or past) versions.  Plugins prefixed with `cwa3_` are tested against Custom Weapons 3.

If you're just here for the plugins, [the releases are up top and, if you're lazy, at this link](https://github.com/nosoop/SM-TFCustomWeaponAttributes/releases).  If you are a curious tinkerer and aspiring SourceMod scripter, read on and see how each thing was made.

## List of attributes:

* `no secondary ammo from dispensers while active`:  Prevents a player with the attribute from acquiring ammo for their secondary weapon.  Uses gamedata with the DHooks extension to detect when the `CObjectDispenser::DispenseAmmo` function is called (so it does not prevent other ammo pickups while being healed by a dispenser), along with touch hooks on ammo packs.
* `exploding sapper`:  A sapper that explodes, with various configurable attributes.  Demonstrates the `player_sapped_object` event and using `tf_generic_bomb` to blow things up with kill credit for a specific player.
* `fires stunballs`:  Replaces the projectile fired from this weapon with Sandman balls.  Demonstrates a lot of reinventing the wheel.
* `per head attack increase`:  Attack speed increases per kill made with weapon.  Originally meant for swords.  Demonstrates an entity think hook to detect weapon use.
* `on kill blast and sentry resist`:  Applies resistances on kill.  Demonstrates overlay?
* `scout bonk override`:  A collection of attributes to implement [Saxton Spinach](https://www.youtube.com/watch?v=f2uOhzM7r-U).
* `minicrits on bleed`:  Is the target bleeding?  Minicrit 'em.  Demonstrates a fake minicrit effect, since there's no good way to distinguish between minicrits and full crits internally.
* `busted booster deploy effect`:  Uses a bunch of filthy workarounds to override the Batallion's Backup effect with one of our own.  In this case, nearby players get a boost to their weapon's firing speed.  I have no idea how I managed to scrape this together.
* `cursed gibs on kill credit`:  Killing a player spawns a bunch of body parts, which gives health on pickup, complete with visual indicator.  There might be copies of body parts.  Couldn't figure out how to make them not collide but still trigger their touch hook.  Oh well.
* `no player ammo pickups`:  Wonder why I didn't just male the gibs ammo drops and just override their touch event?  There's another attribute that prevents players from picking up ammo outright.
* `is tossable teleporter`:  Complete replacement for the Mad Milk.  I improved on the projectile replacement hooks that I abused in `fires stunballs`, and it works even when throwing point-blank.  It also has some really fast unstuck handling to prevent players from getting stuck.
* `damage to heals`:  Damage is returned as heals at a 1:1 exchange rate.  Yummy.  Uses the `player_hurt` event to figure out how much damage to turn to heals.
* `is reassault cannon`:  Dynamic updating of firing rate.  Also uses the rage meter as an indicator for firing speed.
