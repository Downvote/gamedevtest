--!strict
-- Developer names (GAME_DESIGN 5). Pure. A name is a first name and a last name.
local FIRST: { string } = {
	"Mia", "Leo", "Ava", "Noah", "Zoe", "Kai", "Ivy", "Max", "Ruby", "Finn", "Lila", "Omar", "Nina", "Theo", "Maya",
	"Jude", "Aria", "Eli", "Rosa", "Sam", "Tess", "Ravi", "Luna", "Ben", "Cleo", "Hugo", "Iris", "Jin", "Lena", "Milo",
	"Nora", "Otto", "Pia", "Quinn", "Rex", "Suki", "Tom", "Uma", "Vic", "Wren", "Yara", "Zed", "Ada", "Bo", "Cy", "Dot",
}
local LAST: { string } = {
	"Park", "Silva", "Novak", "Ito", "Khan", "Moreau", "Rossi", "Berg", "Lopez", "Okafor", "Chen", "Dube", "Hart", "Kim",
	"Lind", "Mendes", "Nakamura", "Olsen", "Patel", "Quist", "Reyes", "Sato", "Tan", "Vega", "Wolfe", "Young", "Zane",
}

return table.freeze({ first = FIRST, last = LAST })
