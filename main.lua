require "TEsound"

-- mouse position, polled in love.update
local mousex = 0
local mousey = 0

-- total frames the game has been running, used for timing stuff
local totalframes = 0

-- total time the game has been running, used in making sure the logic updates are less dependent on frame rate
local gametime = 0

-- frames per second to aim for, used with gametime to calculate if it's time to update the model
local FPS = 60

-- scale of the images, used when drawing
local imagescale = 16

-- font handle
local font

-- max z-index used, introduced for ease of use
local MAXZ = 10000

-- max z-index for clouds
local CLOUDMAXZ = 40

-- the scene width and height in pixels of the original background images
local SCENESIZE = 32


local scenes = {}
local currentscenename = '' -- this gets set in changeScene

-- all gobs that wants to be updated should be in this table
local currentgobs = {}

-- gobs in the backdrop always gets updated
local backdrop = {
	gobs = {},
	w = SCENESIZE * 5, -- * 5 because it is the total width of the world.
	h = SCENESIZE
}

-- movement speed of the clouds
local wind = 0.01

-- table with all data needed to show text
local hover = {
	lastid = nil,
	text = '',
	x = 0,
	y = 0
}

-- Removed owl, didn't make any sense and was too confusing.
-- specific counter for owl ho-ho
-- local timeinforest = 0

-- specific counter for game over animation
local timetoquit = 0

-- position object
local function newpos(x, y, z)
	if z == nil then
		z = MAXZ
	end
	return {
		x = x,
		y = y,
		z = z
	}
end

-- screen object
local function newscob(image, _imagescale)
	return {
		image = image,
		imagescale = _imagescale or imagescale -- imagescale for default
	}
end

-- click/hover area object
local function newclickarea(imagedata, action, hoveraction)
	return {
		-- alpha 0 pixels does not induce action
		imagedata = imagedata,

		-- called when clicked
		action = action,

		-- called when hovered
		hoveraction = hoveraction,
	}
end

-- scene object, text is the scene text and color will be put on all backdrop objects
local function newscene(text, color, nr, bgsound)
	return {
		visited = false,
		gobs = {},

		-- determines "which clouds" to show
		scenenr = nr,

		-- not used
		text = text,

		-- ambient lighting, colors backdrop stuff like clouds
		color = color or {255, 255, 255},

		-- background sound that plays loopingly while in the scene
		bgsound = bgsound
	}
end


-- gives a unique id with given prefix
local uniqueid
do
	local uniqueidcounter = 0
	uniqueid = function (prefix)
		uniqueidcounter = uniqueidcounter + 1
		return (prefix or 'gob') .. uniqueidcounter
	end
end

-- add gob to scene
local function addGob(scene, id, gob)

	-- the gob should know it's own name
	gob.id = id

	-- set it to the scene's gobs
	scene.gobs[id] = gob

	-- if gob is added while the scene is the current scene it must be added to the currentgobs as well
	if scenes[currentscenename] == scene then
		currentgobs[id] = gob
	end
end


-- creates a cloud with the given distance and adds it to the backdrop
local addCloud
do
	local function moveCloud(self)
		self.pos.x = self.pos.x + wind * 1 / self.distance
		if self.pos.x > backdrop.w then
			self.pos.x = -self.scob.image:getWidth()
		end
	end

	addCloud = function (x, distance, cloudtype)
		addGob(backdrop, uniqueid('cloud'), {
			type = 'cloud',
			distance = distance,
			pos = newpos(x, 1 + distance / 3, SCENESIZE - distance),
			scob = newscob(love.graphics.newImage('cloud' .. cloudtype .. '.png')),
			update = moveCloud
		})
	end
end


-- shine, make a pixel fade in and fade out
local addShine
do 
	local function updateShine(self)
		self.alpha = self.alpha + self.dir * self.speed

		if self.alpha <= 0 then
			self.alpha = 0
			self.dir = 1
		elseif self.alpha >= 1.0 then
			self.alpha = 1.0
			self.dir = -1
		end
	end

	addShine = function (scene, x, y, z, a, speed, color)
		addGob(scene, uniqueid('shine'), {
			type = 'shine',
			speed = speed,
			color = color,
			alpha = a or 0,
			dir = 1,
			pos = newpos(x, y, z),
			scob = newscob(love.graphics.newImage('shine.png')),
			update = updateShine
		})
	end
end


local function addWater(scene, x, y, z, imagepath, color)
	local imagedata = love.image.newImageData(imagepath)
	local imgw = imagedata:getWidth()
	local imgh = imagedata:getHeight()

	for row=0,imgh - 1 do
		for col=0,imgw - 1 do
			local r, g, b, a = imagedata:getPixel(col, row)
			if a > 0 then
				addShine(scene, x + col, y + row, z, g / 255, r / 255 * 0.3, color)
			end
		end
	end
end

-- change current scene
local function changeScene(scenename)

	currentscenename = scenename

	scenes[currentscenename].visited = true

	-- empty the current gobs
	currentgobs = {}

	-- add the new scene's gobs to currentgobs
	for key,gob in pairs(scenes[currentscenename].gobs) do
		currentgobs[key] = gob
	end

	-- add back all backdrop gobs to currentgobs (clouds and such that works across scenes)
	for key,gob in pairs(backdrop.gobs) do
		currentgobs[key] = gob
	end

	-- stop old scene sound
	TEsound.stop('bg')

	-- start new scene sound
	if scenes[currentscenename].bgsound then
		TEsound.playLooping(scenes[currentscenename].bgsound, 'bg')
	end

end


-- checks if point/pixel is inside clickarea, requires gob.pos and gob.clickarea.imagedata
local function clickareahit(x, y, gob)
	local dx = x - math.floor(gob.pos.x)
	local dy = y - math.floor(gob.pos.y)

	if dx >= 0 and -- within image data-range
		dy >= 0 and
		dx < gob.clickarea.imagedata:getWidth() and
		dy < gob.clickarea.imagedata:getHeight() then

		local r,g,b,a = gob.clickarea.imagedata:getPixel(dx, dy)

		-- only opaque pixels can be targeted!
		if not (a == 0) then
			return true
		end
	end
	return false
end


-- sets the hover text, as well as it sets the x y of the hover. Uses id to determine the hovered gob
local function setHover(id, text, x, y)

	-- fix for when setHover is called subsequently, mainly to stop the hover text to move with the mouse while still hovering
	if id == hover.lastid then
		return
	end

	hover.lastid = id
	hover.text = text

	-- if x or y is provided set the hover to the position of the gob with the provided id
	if x == nil then
		x = currentgobs[id].pos.x * imagescale
	end
	if y == nil then
		y = currentgobs[id].pos.y * imagescale
	end

	-- set position
	hover.x = x
	hover.y = y - 22 -- hover should be _above_ mouse pointer and not directly under it
end
local function unsetHover()
	hover.lastid = nil
end

function playSound(sound, vol, pitch)
	if vol == nil then
		vol = 1.0
	end
	if pitch == nil then
		pitch = 1.0
	end
	TEsound.play(sound, nil, vol, pitch)
end

function love.load()

	-- set-up graphics
	love.graphics.setDefaultImageFilter('nearest', 'nearest')
	love.graphics.setLineStyle('rough')

	love.graphics.setMode(32 * imagescale, 32 * imagescale)
	love.graphics.setCaption('X marks the spot')

	-- font = love.graphics.newFont(12)
	font = love.graphics.newImageFont('font.png', ' abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\'\".,!?-:')
	love.graphics.setFont(font)


	-- draw loading message
	love.graphics.setColor(0, 0, 0, 255)
	love.graphics.rectangle('fill', 0, 0, SCENESIZE * imagescale, SCENESIZE * imagescale)
	love.graphics.setColor(200, 200, 200, 255)
	love.graphics.print('Loading', 225, 250)
	love.graphics.present() -- must be called when drawing outside love.draw


	-- backdrop gobs/clouds
	addCloud(8, 1, '1')
	addCloud(0, 3, '2')
	addCloud(30, 1.4, '1')
	addCloud(48, 1.2, '1')
	addCloud(60, 7.2, '2')
	addCloud(82, 8, '1')
	addCloud(90, 1, '2')
	addCloud(96, 1.6, '1')
	addCloud(126, 1.1, '1')
	addCloud(122, 5, '2')


	-- init beach
	scenes.beach = newscene('a soothing beach', {216, 245, 255}, 0, 'sounds/beach.ogg')

	addGob(scenes.beach, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('beach.png')),
	})

	-- sea
	addWater(scenes.beach, 0, 0, 1, 'beach_watermask_waves.png', {180, 243, 255, 155})
	addWater(scenes.beach, 0, 0, 2, 'beach_watermask.png', {235, 255, 255, 100})

	addGob(scenes.beach, 'bottle', {
		pos = newpos(5, 29, 10),
		scob = newscob(love.graphics.newImage('beach_bottle.png')),
		clickarea = newclickarea(
			love.image.newImageData('beach_bottle.png'),
			function (self)
				if scenes.beach.gobs.note then return end
				if self.bottleinwater then
					playSound('sounds/bottle.ogg')
					self.pos.x = 17
					self.pos.y = 28
					self.bottleinwater = false
					return
				end

				playSound('sounds/prassel.ogg', 0.4, 1.5)
				addGob(scenes.beach, 'note', {
					pos = newpos(18, 28, 20),
					scob = newscob(love.graphics.newImage('beach_note.png')),
					clickarea = newclickarea(
						love.image.newImageData('beach_note.png'),
						function () 
							hover.text = '"If you\'re reading this, I managed to get off that bloody island."'
							-- hover.text = '"I couldn\'t just leave. I had so much procrastination left to do."'
							-- hover.text = 'it says: \"It is not procrastination if it keeps your mind busy.\"'
						end,
						function (self) setHover(self.id, 'note') end
					)
				})
			end,
			function (self)
				setHover(self.id, 'bottle')
			end
		),
		bottleinwater = true,
		dir = 1,
		update = function (self)
			if not self.bottleinwater then self.update = nil end

			if self.pos.y > 28.7 and self.dir == 1 then
				self.dir = -1
			elseif self.pos.y < 28.2 and self.dir == -1 then
				self.dir = 1
			end
			self.pos.y = self.pos.y + 0.005 * self.dir
		end
	})

	addGob(scenes.beach, 'clickarea_gotohouse', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('house') end,
			function (self) 
				if scenes.house.visited then 
					setHover(self.id, 'go to the house', mousex, mousey) 
				else
					setHover(self.id, 'the smell of grass...', mousex, mousey) 
				end
			end
		)
	})

	-- init house
	scenes.house = newscene('a house', {219, 255, 219}, 1, 'sounds/genericwind.ogg')

	addGob(scenes.house, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('house.png'))
	})

	addGob(scenes.house, 'treemessage', {
		pos = newpos(6, 22, 1),
		clickarea = newclickarea(
			love.image.newImageData('beach_note.png'),
			function (self) hover.text = 'it says: \"I was here too long, but not long enough\"' end,
			function (self) setHover(self.id, 'carved text') end
		)
	})

	addGob(scenes.house, 'clickarea_door', {
		pos = newpos(15, 20, 1),
		knocked = false,
		clickarea = newclickarea(
			love.image.newImageData('house_doorclickarea.png'),
			function (self)
				playSound('sounds/house_door.ogg', 0.4, 1.5)
				changeScene('insideofhouse')
			end,
			function (self) setHover(self.id, 'door', mousex, mousey) end
		)
	})

	addGob(scenes.house, 'clickarea_gotobeach', {
		pos = newpos(0, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('beach') end,
			function (self) setHover(self.id, 'go to the beach', mousex, mousey) end
		)
	})

	addGob(scenes.house, 'clickarea_gotowaterfall', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('waterfall') end,
			function (self) 
				if scenes.waterfall.visited then
					setHover(self.id, 'go to the waterfall', mousex, mousey)
				else
					setHover(self.id, 'something is splashing...', mousex, mousey)
				end
			end
		)
	})


	-- init inside of house
	scenes.insideofhouse = newscene('inside of house', {219, 255, 219}, 1)

	addGob(scenes.insideofhouse, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('insidehouse.png'))
	})

	addGob(scenes.insideofhouse, 'wall', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('insidehouse_wall.png'))
	})

	addGob(scenes.insideofhouse, 'map', {
		pos = newpos(6, 14, CLOUDMAXZ + 2),
		scob = newscob(love.graphics.newImage('insidehouse_map.png')),
		clicked = false,
		clickarea = newclickarea(
			love.image.newImageData('insidehouse_map.png'),
			function (self)
				self.clicked = true
				playSound('sounds/longprassel.ogg', 0.3, 0.7)
				changeScene('map')
			end,
			function (self) setHover(self.id, 'map') end
		)
	})

	addGob(scenes.insideofhouse, 'clickarea_gotohouse', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self) 
				playSound('sounds/insidehouse_leave.ogg', 0.3, 0.7)
				changeScene('house')
			end,
			function (self) setHover(self.id, 'leave', mousex, mousey) end
		)
	})


	-- init map
	scenes.map = newscene('map', {255, 255, 255}, 1)

	addGob(scenes.map, 'map', {
		pos = newpos(0, 0, MAXZ - 2),
		scob = newscob(love.graphics.newImage('map.png'))
	})

	addGob(scenes.map, 'clickarea_gotoinsideofhouse', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self)
				playSound('sounds/map.ogg', 0.5)
				changeScene('insideofhouse')
			end,
			function (self) setHover(self.id, 'put down the map', mousex, mousey) end
		)
	})
	

	-- init waterfall
	scenes.waterfall = newscene('waterfall', {219, 255, 219}, 2, 'sounds/waterfall.ogg')

	addGob(scenes.waterfall, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('waterfall.png'))
	})

	addGob(scenes.waterfall, 'waterfall', {
		pos = newpos(25, 5, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('waterfall_waterfall.png'))
	})

	-- waterfall and lake
	addWater(scenes.waterfall, 0, 0, CLOUDMAXZ + 2, 'waterfall_watermask.png', {255, 255, 200, 55})

	addGob(scenes.waterfall, 'clickarea_gotohouse', {
		pos = newpos(0, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('house') end,
			function (self) setHover(self.id, 'go to the house', mousex, mousey) end
		)
	})

	addGob(scenes.waterfall, 'clickarea_gotobehindwaterfall', {
		pos = newpos(25, 15, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('waterfall_waterfallclickarea.png'),
			function (self) changeScene('behindwaterfall') end,
			function (self) setHover(self.id, 'go through the waterfall', mousex, mousey) end
		)
	})

	-- init cave behind waterfall
	scenes.behindwaterfall = newscene('behindwaterfall', {255, 255, 255}, 3, 'sounds/behindwaterfall.ogg')

	addGob(scenes.behindwaterfall, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ),
		scob = newscob(love.graphics.newImage('behindwaterfall.png'))
	})

	-- waterfall
	addWater(scenes.behindwaterfall, 0, 0, CLOUDMAXZ + 1, 'behindwaterfall_watermask.png', {41, 60, 83, 255})

	addGob(scenes.behindwaterfall, 'clickarea_gotowaterfall', {
		pos = newpos(0, 3, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('behindwaterfall_waterfallclickarea.png'),
			function (self) changeScene('waterfall') end,
			function (self) setHover(self.id, 'go back through the waterfall', mousex, mousey) end
		)
	})

	addGob(scenes.behindwaterfall, 'clickarea_gotoskeletoncave', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('skeletoncave') end,
			function (self) 
				if scenes.skeletoncave.visited then
					setHover(self.id, 'go to the skeleton cave', mousex, mousey)
				else
					setHover(self.id, 'go deeper', mousex, mousey)
				end
			end
		)
	})

	addGob(scenes.behindwaterfall, 'hole', {
		pos = newpos(20, 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('behindwaterfall_hole.png'),
			function (self) changeScene('church') end,
			function (self) setHover(self.id, 'climb up') end
		)
	})

	addGob(scenes.behindwaterfall, 'pebbles_box', {
		pos = newpos(14, 27, MAXZ),
		scob = newscob(love.graphics.newImage('pebbles_box.png')),
		clickarea = newclickarea(
			love.image.newImageData('pebbles_box.png'),
			function (self)
				playSound('sounds/pebbles.ogg')
				self.scob = newscob(love.graphics.newImage('pebbles_scrambled.png'))
				self.clickarea.imagedata = love.image.newImageData('pebbles_scrambled.png')
				self.scrambled = true
			end,
			function (self) 
				if self.scrambled then
					setHover(self.id, 'scrambled pebbles', mousex, mousey)
				else
					setHover(self.id, 'pebbles layed out in the shape of a box', mousex, mousey)
				end
			end
		),
		scrambled = false
	})

	-- init skeleton cave
	scenes.skeletoncave = newscene('skeletoncave', {255, 255, 255}, 4, 'sounds/skeletoncave.ogg')

	addGob(scenes.skeletoncave, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ),
		scob = newscob(love.graphics.newImage('skeletoncave.png'))
	})

	addGob(scenes.skeletoncave, 'clickarea_gotobehindwaterfall', {
		pos = newpos(0, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('behindwaterfall') end,
			function (self) setHover(self.id, 'go back', mousex, mousey) end
		)
	})

	addGob(scenes.skeletoncave, 'skeleton', {
		pos = newpos(18, 23, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('skeletoncave_skeleton.png')),
		clickarea = newclickarea(
			love.image.newImageData('skeletoncave_skeleton.png'),
			function (self)
				if scenes.skeletoncave.gobs.wallet then 
					return
				end
				playSound('sounds/prassel.ogg', 0.4)
				addGob(scenes.skeletoncave, 'wallet', {
					pos = newpos(10, 25, CLOUDMAXZ + 2),
					scob = newscob(love.graphics.newImage('skeletoncave_wallet.png')),
					clickarea = newclickarea(
						love.image.newImageData('skeletoncave_wallet.png'),
						function (self)
							if scenes.skeletoncave.gobs.id then
								return
							end
							playSound('sounds/prassel.ogg', 0.4, 2.0)
							addGob(scenes.skeletoncave, 'id', {
								pos = newpos(12, 26, CLOUDMAXZ + 3),
								scob = newscob(love.graphics.newImage('skeletoncave_id.png')),
								clickarea = newclickarea(
									love.image.newImageData('skeletoncave_id.png'),
									function (self) hover.text = '"Mr. Fredrik Vestin"' end,
									function (self) setHover(self.id, 'driver\'s license') end
								)
							})
						end,
						function (self) setHover(self.id, 'wallet') end
					)
				})
			end,
			function (self) setHover(self.id, 'skeleton', mousex, mousey) end
		)
	})


	-- init church
	scenes.church = newscene('church', {219, 255, 219}, 3, 'sounds/genericwind.ogg')

	addGob(scenes.church, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('church.png'))
	})

	addGob(scenes.church, 'hole', {
		pos = newpos(3, 29, MAXZ),
		scob = newscob(love.graphics.newImage('church_hole.png')),
		clickarea = newclickarea(
			love.image.newImageData('church_hole.png'),
			function (self) changeScene('behindwaterfall') end,
			function (self) setHover(self.id, 'climb down') end
		)
	})

	addGob(scenes.church, 'church', {
		pos = newpos(13, 1, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('church_church.png'))
	})

	addGob(scenes.church, 'door', {
		pos = newpos(19, 17, MAXZ),
		scob = newscob(love.graphics.newImage('church_door.png')),
		clickarea = newclickarea(
			love.image.newImageData('church_door.png'),
			function (self)
				playSound('sounds/church_door.ogg')
				changeScene('insidechurchright')
			end,
			function (self) setHover(self.id, 'enter', mousex, mousey) end
		)
	})

	addGob(scenes.church, 'clickarea_gotoforest', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('forest') end,
			function (self) 
				if scenes.forest.visited then
					setHover(self.id, 'go to the forest', mousex, mousey)
				else
					setHover(self.id, 'follow the trail', mousex, mousey)
				end
			end
		)
	})


	-- init inside church left
	scenes.insidechurchleft = newscene('insidechurchleft', {255, 255, 255}, 3)

	addGob(scenes.insidechurchleft, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('insidechurchleft.png'))
	})

	addGob(scenes.insidechurchleft, 'walls', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('insidechurchleft_wall.png'))
	})

	addGob(scenes.insidechurchleft, 'book', {
		pos = newpos(26, 14, CLOUDMAXZ + 2),
		scob = newscob(love.graphics.newImage('insidechurchleft_book.png')),
		clickarea = newclickarea(
			love.image.newImageData('insidechurchleft_book.png'),
			function (self)
				scenes.insidechurchleft.gobs.book = nil
				playSound('sounds/church_book.ogg', 0.5)
				addGob(scenes.insidechurchleft, 'open_book', {
					pos = newpos(25, 14, CLOUDMAXZ + 2),
					scob = newscob(love.graphics.newImage('insidechurchleft_openbook.png')),
					clickarea = newclickarea(
						love.image.newImageData('insidechurchleft_openbook.png'),
						function (self) hover.text = '"A Truth is only True if it has Believers."' end,
						function (self) setHover(self.id, 'read') end
					)
				})
			end,
			function (self) setHover(self.id, 'book') end
		)
	})

	addGob(scenes.insidechurchleft, 'clickarea_gotochurch', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self)
				playSound('sounds/church_door.ogg', 0.3)
				changeScene('church')
			end,
			function (self) setHover(self.id, 'leave', mousex, mousey) end
		)
	})

	addGob(scenes.insidechurchleft, 'clickarea_lookright', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ - 1),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('insidechurchright') end,
			function (self) 
				setHover(self.id, 'look right', mousex, mousey)
			end
		)
	})

	-- init inside church right
	scenes.insidechurchright = newscene('insidechurchright', {219, 255, 219}, 3)

	addGob(scenes.insidechurchright, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('insidechurchright.png'))
	})

	-- candle
	addShine(scenes.insidechurchright, 3, 11, CLOUDMAXZ + 2, 0.6, 0.091, {255, 190, 83, 200})
	addShine(scenes.insidechurchright, 3, 11, CLOUDMAXZ + 2, 0.45, 0.067, {255, 245, 0, 155})
	addShine(scenes.insidechurchright, 3, 11, CLOUDMAXZ + 2, 0, 0.006, {255, 130, 0, 140})

	addGob(scenes.insidechurchright, 'clickarea_candle', {
		pos = newpos(3, 11, MAXZ - 2),
		clickarea = newclickarea(
			love.image.newImageData('water.png'),
			function (self) 
				playSound('sounds/church_blowout.ogg', 0.8, 1.5)
				for i,gob in pairs(scenes.insidechurchright.gobs) do
					if string.find(gob.id, 'shine') then
						currentgobs[gob.id] = nil
					end
				end
				currentgobs[self.id] = nil
			end,
			function (self)
				setHover(self.id, 'blow out', mousex, mousey)
			end
		)
	})

	addGob(scenes.insidechurchright, 'clickarea_gotochurch', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self)
				playSound('sounds/church_door.ogg', 0.3)
				changeScene('church')
			end,
			function (self) setHover(self.id, 'leave', mousex, mousey) end
		)
	})

	addGob(scenes.insidechurchright, 'clickarea_lookleft', {
		pos = newpos(0, SCENESIZE - 28, MAXZ - 1),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('insidechurchleft') end,
			function (self) 
				setHover(self.id, 'look left', mousex, mousey)
			end
		)
	})

	-- init forest
	scenes.forest = newscene('forest', {219, 255, 219}, 4, 'sounds/genericwind.ogg')

	addGob(scenes.forest, 'bg', {
		pos = newpos(0, 0, 0),
		scob = newscob(love.graphics.newImage('forest.png'))
	})

	addGob(scenes.forest, 'forest', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('forest_forest.png'))
	})

	addGob(scenes.forest, 'sign', {
		pos = newpos(17, 21, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('forest_sign.png'),
			function (self) hover.text = '"The Forest Of Trees"' end,
			function (self) setHover(self.id, 'trail sign') end
		)
	})

	addGob(scenes.forest, 'clickarea_entrance', {
		pos = newpos(15, 23, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('forest_entrance.png'),
			function (self)
				-- timeinforest = totalframes
				changeScene('insideforest1')
			end,
			function (self) setHover(self.id, 'enter', mousex, mousey) end
		)
	})

	addGob(scenes.forest, 'clickarea_gotochurch', {
		pos = newpos(0, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('church') end,
			function (self) setHover(self.id, 'go to the church', mousex, mousey) end
		)
	})

	addGob(scenes.forest, 'clickarea_gotoendoftheworld', {
		pos = newpos(SCENESIZE - 2, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('endoftheworld') end,
			function (self) 
				setHover(self.id, 'go further', mousex, mousey)
			end
		)
	})


	-- init insideforest1
	scenes.insideforest1 = newscene('insideforest1', {219, 255, 219}, 4)

	addGob(scenes.insideforest1, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('insideforest1.png'))
	})

	addGob(scenes.insideforest1, 'clickarea_gotonext', {
		pos = newpos(0, 0, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest1_gotonext.png'),
			function () changeScene('insideforest2') end,
			function (self) setHover(self.id, 'follow the trail', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest1, 'clickarea_mushroom1', {
		pos = newpos(10, 25, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest1_mushroom1.png'),
			function () hover.text = 'it looks deadly' end,
			function (self) setHover(self.id, 'mushroom', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest1, 'clickarea_mushroom2', {
		pos = newpos(23, 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest1_mushroom2.png'),
			function () hover.text = 'it looks delicous and poisonous' end,
			function (self) setHover(self.id, 'mushroom', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest1, 'clickarea_gotoforest', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self) changeScene('forest') end,
			function (self) setHover(self.id, 'exit', mousex, mousey) end
		)
	})

	-- init insideforest2
	scenes.insideforest2 = newscene('insideforest2', {219, 255, 219}, 4)

	addGob(scenes.insideforest2, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('insideforest2.png'))
	})

	addGob(scenes.insideforest2, 'clickarea_gotonext', {
		pos = newpos(0, 0, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest1_gotonext.png'),
			function () changeScene('forest') end,
			function (self) setHover(self.id, 'it looks as if it gets brighter around the corner', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest2, 'clickarea_rock', {
		pos = newpos(0, 0, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest2_rock.png'),
			function () hover.text = 'weighs a lot' end,
			function (self) setHover(self.id, 'big rock', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest2, 'clickarea_stub', {
		pos = newpos(0, 0, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('insideforest2_stub.png'),
			function () hover.text = 'completely hollow' end,
			function (self) setHover(self.id, 'stub', mousex, mousey) end
		)
	})

	addGob(scenes.insideforest2, 'clickarea_gotoforest', {
		pos = newpos(0, SCENESIZE - 2, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullvertical.png'),
			function (self) changeScene('insideforest1') end,
			function (self) setHover(self.id, 'go back', mousex, mousey) end
		)
	})


	-- init end of the world
	scenes.endoftheworld = newscene('endoftheworld', {219, 255, 219}, 5, 'sounds/endoftheworld.ogg')

	addGob(scenes.endoftheworld, 'bg', {
		pos = newpos(0, 0, CLOUDMAXZ + 1),
		scob = newscob(love.graphics.newImage('endoftheworld.png'))
	})

	addGob(scenes.endoftheworld, 'clickarea_gotoforest', {
		pos = newpos(0, SCENESIZE - 28, MAXZ),
		clickarea = newclickarea(
			love.image.newImageData('nextscene_fullside.png'),
			function (self) changeScene('forest') end,
			function (self) setHover(self.id, 'go to the forest', mousex, mousey) end
		)
	})

	addGob(scenes.endoftheworld, 'sign', {
		pos = newpos(7, 16, CLOUDMAXZ + 2),
		clicked = false,
		clickarea = newclickarea(
			love.image.newImageData('endoftheworld_signclickarea.png'),
			function (self)
				if not scenes.insideofhouse.gobs.map.clicked then
					hover.text = '"Did the map in the house help?"'
				else
					self.clicked = true
					hover.text = '"End of the World"'
				end
			end,
			-- function (self) hover.text = 'it reads: "Answers are Consequences of Questions"' end,
			function (self) setHover(self.id, 'the sign') end
		)
	})

	addGob(scenes.endoftheworld, 'rainbow_clickarea', {
		pos = newpos(0, 0, CLOUDMAXZ + 2),
		clickarea = newclickarea(
			love.image.newImageData('endoftheworld_rainbowclickarea.png'),
			function (self)
				if scenes.insideofhouse.gobs.map.clicked then
					hover.text = '"What does it mean?"'
				end
			end,
			function (self) setHover(self.id, '', mousex, mousey) end
		)
	})

	-- ...I don't like when loading just flickers by...
	love.timer.sleep(1)

	-- start game
	changeScene('house')

end

-- only for quick testing
-- function love.keypressed(key)
-- 	if key == 'escape' then
-- 		love.event.push('quit')
-- 	end
-- end

function love.quit()
	TEsound.stop('bg')

	-- begin endoftheworld animation
	if currentscenename == 'endoftheworld' and scenes.endoftheworld.gobs.sign.clicked and timetoquit == 0 then
		timetoquit = totalframes
		return true -- tell the OS not to exit
	end
	return false -- tell the OS to exit
end

-- y u no work?
-- function love.focus(focus)
-- 	if focus then
-- 		TEsound.tagVolume('all', 1.0)
-- 	else 
-- 		TEsound.tagVolume('all', 0.0)
-- 	end
-- end

function love.mousepressed(x, y)

	-- take graphics scaling into account
	x = math.floor(x / imagescale)
	y = math.floor(y / imagescale)

	-------- CLICK ACTION ------------
	zarr = {}

	-- get all clickareas which are in the mouse position
	for id,gob in pairs(currentgobs) do
		if gob.clickarea and gob.clickarea.action and clickareahit(x, y, gob) then
			table.insert(zarr, gob)
		end
	end

	-- sort, to the one with highest z value first
	table.sort(zarr, function (a, b) return a.pos.z > b.pos.z end)

	-- call the action
	if zarr[1] then
		zarr[1].clickarea.action(zarr[1])
	end

end

function love.update(dt)

	-- sound cleanup
	TEsound.cleanup()

	-------- MOUSE INPUT -------------
	mousex, mousey = love.mouse.getPosition()


	-------- HOVER ACTION ------------ (click action is done in love.mouse.pressed)
	local x = math.floor(mousex / imagescale)
	local y = math.floor(mousey / imagescale)

	-- get the gobs where the mouse is hovering
	zarr = {}

	for id,gob in pairs(currentgobs) do
		if gob.clickarea and gob.clickarea.hoveraction and clickareahit(x, y, gob) then -- hoveraction must be present to make sense
			table.insert(zarr, gob)
		end
	end

	-- sort by z, highest z first
	table.sort(zarr, function (a, b) return a.pos.z > b.pos.z end)

	-- take out the first gob and do hoveraction
	if zarr[1] then -- already checked for hoveraction presence, when plucked from scene and backdrop
		zarr[1].clickarea.hoveraction(zarr[1])
	else
		unsetHover()
	end




	-------- UPDATE MODEL ------------

	-- only update logic in 60 fps
	gametime = gametime + dt
	if gametime < 1 / FPS then
		return
	end
	gametime = 0
	totalframes = totalframes + 1

	-- close 2 seconds after the player succeeded, if the player succeeded
	if timetoquit > 0 and totalframes - timetoquit > 120 then
		love.event.push('quit')
	end

	-- if timetoquit > 0 then
	-- 	TEsound.tagVolume('all', 0.0)
	-- 	return
	-- end

	-- update gobs
	for id,gob in pairs(currentgobs) do
		if gob.update then
			gob.update(gob)
		end
	end

	-- specific timing and invocation of the owl sound in the forest
	-- if timeinforest > 0 and
	-- 		totalframes - timeinforest > 60 * 11 and
	-- 		(currentscenename == 'insideforest1' or currentscenename == 'insideforest2') then
	-- 	playSound('sounds/owl.ogg')
	-- 	timeinforest = 0
	-- end

end


function love.draw()

	-- if player succeeded, show black background and fade in white game over text
	if timetoquit > 0 then
		local c = 255 / 60 * (totalframes - timetoquit);
		if c > 255 then c = 255 end
		love.graphics.setColor(0, 0, 0, 255)
		love.graphics.rectangle('fill', 0, 0, SCENESIZE * imagescale, SCENESIZE * imagescale)
		love.graphics.setColor(c, c, c, 255)
		love.graphics.print('You found the spot', 185, 250)
		return -- don't draw anything else
	end

	-- init scalem, ambient color and backdrop offsets
	love.graphics.scale(imagescale)
	local c = scenes[currentscenename].color
	local sceneoffsetx = -scenes[currentscenename].scenenr * SCENESIZE

	-- sort gobs in z-order, lowest to highest
	zarr = {}
	for id,gob in pairs(currentgobs) do
		if gob.scob then
			table.insert(zarr, gob)
		end
	end
	table.sort(zarr, function (a, b) return a.pos.z < b.pos.z end)

	-- draw z-ordered gobs
	for id,gob in ipairs(zarr) do
		local offx = 0
		love.graphics.setBlendMode('alpha')

		-- set scene color if gob is backdrop gob, else just pure white
		if backdrop.gobs[gob.id] then
			if gob.type == 'cloud' then
				love.graphics.setColor(c[1], c[2], c[3], 55 + 200 * (1 / gob.distance))
			else
				love.graphics.setColor(c[1], c[2], c[3], 255)
			end

			offx = sceneoffsetx
		else
			if gob.type == 'shine' then
				local c = gob.color
				love.graphics.setColor(c[1], c[2], c[3], math.floor(c[4] * gob.alpha))
			else
				love.graphics.setColor(255, 255, 255, 255)
			end
		end

		-- draw the gob
		love.graphics.draw(gob.scob.image, gob.pos.x + offx, gob.pos.y)
	end

	-- draw scene text
	love.graphics.scale(1 / imagescale) -- reset after images
	love.graphics.setBlendMode('alpha') -- reset after drawing shines

	-- draw hover
	if hover.lastid and not (hover.text == '') then

		-- initiate with black text on white background
		local c1 = 255
		local c2 = 0

		-- position and width dependant on text
		local w = font:getWidth(hover.text)
		local x = hover.x - w / 2

		local padding = 6

		-- if in certain dark scenes, text should be white on black background
		if currentscenename == 'behindwaterfall' or 
			currentscenename == 'skeletoncave'  or
			currentscenename == 'insideforest1' or
			currentscenename == 'insideforest2' then
			c1 = 9
			c2 = 255
		end

		-- determine x with regards to not drawing text outside the window
		if hover.x + w / 2 > SCENESIZE * imagescale then
			x = SCENESIZE * imagescale - w - padding
		elseif hover.x - w / 2 < 0 then
			x = 0 + padding
		end
		x = math.floor(x)

		-- draw hover background
		love.graphics.setColor(c1, c1, c1, 155)
		love.graphics.rectangle('fill', x - padding, hover.y - padding, w + padding * 2, 18 + padding * 2)

		-- draw text
		love.graphics.setColor(c2, c2, c2, 255)
		love.graphics.print(hover.text, x, hover.y)
	end

end
