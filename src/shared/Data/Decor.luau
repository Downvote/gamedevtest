--!strict
-- Outdoor decor for the plot (GAME_DESIGN 9). Pure. A piece is bought once (price in coins) and placed as many times
-- as the plot's piece limit allows (Logic/Plot). w x d: its footprint in whole studs facing south (a quarter turn swaps
-- them); Models/DecorModels builds it.
export type DecorDef = { id: string, name: string, price: number, w: number, d: number }

local LIST: { DecorDef } = {
	{ id = "gnome", name = "Garden Gnome", price = 1000, w = 1, d = 1 },
	{ id = "flowers", name = "Flower Bed", price = 2500, w = 2, d = 2 },
	{ id = "bush", name = "Round Bush", price = 2000, w = 2, d = 2 },
	{ id = "bench", name = "Park Bench", price = 4000, w = 3, d = 2 },
	{ id = "lamp", name = "Street Lamp", price = 4500, w = 1, d = 1 },
	{ id = "oak", name = "Oak Tree", price = 7500, w = 3, d = 3 },
	{ id = "pine", name = "Pine Tree", price = 7500, w = 3, d = 3 },
	{ id = "bikes", name = "Bike Rack", price = 6000, w = 3, d = 2 },
	{ id = "picnic", name = "Picnic Table", price = 12500, w = 4, d = 3 },
	{ id = "kiosk", name = "Arcade Kiosk", price = 30000, w = 2, d = 2 },
	{ id = "fountain", name = "Fountain", price = 60000, w = 5, d = 5 },
	{ id = "statue", name = "Hero Statue", price = 100000, w = 3, d = 3 },
	{ id = "dish", name = "Satellite Dish", price = 125000, w = 3, d = 3 },
	{ id = "billboard", name = "Billboard", price = 150000, w = 6, d = 2 },
	{ id = "truck", name = "Food Truck", price = 200000, w = 6, d = 3 },
}

local BY_ID: { [string]: DecorDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
