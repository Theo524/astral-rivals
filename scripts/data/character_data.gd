extends RefCounted
## All combat identities are data driven; visuals consume the same palette.
static func roster() -> Array[Dictionary]:
	return [
		{"id":"kaizen", "name":"KAIZEN", "title":"The Celestial Warrior", "color":Color("49cfff"), "outfit":Color("145ec0"), "hair":Color("101a30"), "skin":Color("eab58d"), "hp":1100.0, "speed":9.3, "power":1.0, "energy_rate":1.0, "special":"CELESTIAL TORRENT", "ultimate":"STARFALL JUDGEMENT", "style":"Balanced • swift combos", "form_names":["BASE", "GOLDEN AWAKENING", "CELESTIAL ASCENDANT"]},
		{"id":"ryuzen", "name":"RYUZEN", "title":"The Shadow Champion", "color":Color("b784ff"), "outfit":Color("29243f"), "hair":Color("555666"), "skin":Color("d7a48c"), "hp":1200.0, "speed":10.0, "power":1.12, "energy_rate":0.85, "special":"VOID LANCER", "ultimate":"CRIMSON ECLIPSE", "style":"Pressure • devastating melee", "form_names":["BASE", "SHADOW AWAKENING", "CRIMSON SOVEREIGN"]},
		{"id":"akira", "name":"AKIRA", "title":"The Solar Guardian", "color":Color("ffb543"), "outfit":Color("eee8d9"), "hair":Color("b72e26"), "skin":Color("edb99a"), "hp":1000.0, "speed":8.8, "power":0.94, "energy_rate":1.25, "special":"SOLAR FLARE", "ultimate":"RADIANT SUPERNOVA", "style":"Range • amplified energy", "form_names":["BASE", "SOLAR AWAKENING", "RADIANT INFINITY"]}
	]
