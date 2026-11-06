--!strict
-- Outdoor decor for the plot (GAME_DESIGN 13). Pure. A piece is bought once (price, and its fans join the studio
-- then) and placed as many times as the plot's piece limit allows (Logic/Plot). w x d: its footprint in whole studs
-- facing south (a quarter turn swaps them); office: the office tier it needs; Models/DecorModels builds it.
export type DecorDef = { id: string, name: string, price: number, fans: number, w: number, d: number, office: number }

local LIST: { DecorDef } = {
	{ id = "gnome", name = "Garden Gnome", price = 200, fans = 5, w = 1, d = 1, office = 1 },
	{ id = "flowers", name = "Flower Bed", price = 500, fans = 20, w = 2, d = 2, office = 1 },
	{ id = "bush", name = "Round Bush", price = 400, fans = 15, w = 2, d = 2, office = 1 },
	{ id = "bench", name = "Park Bench", price = 800, fans = 25, w = 3, d = 2, office = 1 },
	{ id = "lamp", name = "Street Lamp", price = 900, fans = 25, w = 1, d = 1, office = 1 },
	{ id = "oak", name = "Oak Tree", price = 1500, fans = 40, w = 3, d = 3, office = 1 },
	{ id = "pine", name = "Pine Tree", price = 1500, fans = 40, w = 3, d = 3, office = 1 },
	{ id = "bikes", name = "Bike Rack", price = 1200, fans = 30, w = 3, d = 2, office = 1 },
	{ id = "picnic", name = "Picnic Table", price = 2500, fans = 60, w = 4, d = 3, office = 1 },
	{ id = "kiosk", name = "Arcade Kiosk", price = 6000, fans = 150, w = 2, d = 2, office = 2 },
	{ id = "fountain", name = "Fountain", price = 12000, fans = 300, w = 5, d = 5, office = 2 },
	{ id = "statue", name = "Hero Statue", price = 20000, fans = 500, w = 3, d = 3, office = 2 },
	{ id = "dish", name = "Satellite Dish", price = 25000, fans = 600, w = 3, d = 3, office = 3 },
	{ id = "billboard", name = "Billboard", price = 30000, fans = 800, w = 6, d = 2, office = 3 },
	{ id = "truck", name = "Food Truck", price = 40000, fans = 1000, w = 6, d = 3, office = 3 },
}

local BY_ID: { [string]: DecorDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
