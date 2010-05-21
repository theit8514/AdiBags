--[[
AdiBags - Adirelle's bag addon.
Copyright 2010 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

local ITEM_SIZE = addon.ITEM_SIZE
local ITEM_SPACING = addon.ITEM_SPACING
local SECTION_SPACING = addon.SECTION_SPACING
local SLOT_OFFSET = ITEM_SIZE + ITEM_SPACING
local HEADER_SIZE = 14 + ITEM_SPACING
addon.HEADER_SIZE = HEADER_SIZE

--------------------------------------------------------------------------------
-- Section ordering
--------------------------------------------------------------------------------

local categoryOrder = {
	[L["Free space"]] = -100
}

function addon:SetCategoryOrder(name, order)
	categoryOrder[name] = order
end

function addon:SetCategoryOrders(t)
	for name, order in pairs(t) do
		categoryOrder[name] = order
	end
end

--------------------------------------------------------------------------------
-- Initialization and release
--------------------------------------------------------------------------------

local sectionClass, sectionProto = addon:NewClass("Section", "Frame")
addon:CreatePool(sectionClass, "AcquireSection")

function sectionProto:OnCreate()
	self.buttons = {}
	self.slots = {}
	self.freeSlots = {}

	local header = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", SECTION_SPACING - ITEM_SPACING, 0)
	header:SetHeight(HEADER_SIZE)
	self.Header = header
	addon:SendMessage('AdiBags_SectionCreated', self)
end

function sectionProto:OnAcquire(container, name, category)
	self:SetParent(container)
	self.Header:SetText(name)
	self.name = name
	self.category = category or name
	self.width = 0
	self.height = 0
	self.count = 0
	self.total = 0
	self.container = container
end

function sectionProto:ToString()
	return string.format("Section[%q,%q]", tostring(self.name), tostring(self.category))
end

function sectionProto:OnRelease()
	wipe(self.freeSlots)
	wipe(self.slots)
	wipe(self.buttons)
	self.name = nil
	self.category = nil
	self.container = nil
end

function sectionProto:GetOrder()
	return self.category and categoryOrder[self.category] or 0
end

--------------------------------------------------------------------------------
-- Button handling
--------------------------------------------------------------------------------

function sectionProto:AddItemButton(slotId, button)
	if not self.buttons[button] then
		button:SetSection(self)
		self.buttons[button] = slotId
		local freeSlots = self.freeSlots
		for index = 1, self.total do
			if freeSlots[index] then
				self:PutButtonAt(button, index)
				return
			end
		end
		self.dirtyLayout = true
	end
end

function sectionProto:RemoveItemButton(button)
	if self.buttons[button] then
		local index = self.slots[button]
		if index and index <= self.total then
			self.freeSlots[index] = true
		end
		self.slots[button] = nil
		self.buttons[button] = nil
	end
end

function sectionProto:DispatchDone()
	local newCount = 0
	for button in pairs(self.buttons) do
		newCount = newCount + 1
	end
	if (newCount == 0 and self.count > 0) or newCount > self.total then
		self.dirtyLayout = true
	end
	self.count = newCount
	self:Debug(newCount, 'buttons')
	return self.dirtyLayout
end

--------------------------------------------------------------------------------
-- Item sorting
--------------------------------------------------------------------------------

local EQUIP_LOCS = {
	INVTYPE_AMMO = 0,
	INVTYPE_HEAD = 1,
	INVTYPE_NECK = 2,
	INVTYPE_SHOULDER = 3,
	INVTYPE_BODY = 4,
	INVTYPE_CHEST = 5,
	INVTYPE_ROBE = 5,
	INVTYPE_WAIST = 6,
	INVTYPE_LEGS = 7,
	INVTYPE_FEET = 8,
	INVTYPE_WRIST = 9,
	INVTYPE_HAND = 10,
	INVTYPE_FINGER = 11,
	INVTYPE_TRINKET = 13,
	INVTYPE_CLOAK = 15,
	INVTYPE_WEAPON = 16,
	INVTYPE_SHIELD = 17,
	INVTYPE_2HWEAPON = 16,
	INVTYPE_WEAPONMAINHAND = 16,
	INVTYPE_WEAPONOFFHAND = 17,
	INVTYPE_HOLDABLE = 17,
	INVTYPE_RANGED = 18,
	INVTYPE_THROWN = 18,
	INVTYPE_RANGEDRIGHT = 18,
	INVTYPE_RELIC = 18,
	INVTYPE_TABARD = 19,
	INVTYPE_BAG = 20,
}

local sortingFuncs = {

	default = function(idA, idB)
		local nameA, _, qualityA, levelA, _, classA, subclassA, _, equipSlotA = GetItemInfo(idA)
		local nameB, _, qualityB, levelB, _, classB, subclassB, _, equipSlotB = GetItemInfo(idB)
		local equipLocA = EQUIP_LOCS[equipSlotA or ""]
		local equipLocB = EQUIP_LOCS[equipSlotB or ""]
		if equipLocA and equipLocB and equipLocA ~= equipLocB then
			return equipLocA < equipLocB
		elseif classA ~= classB then
			return classA < classB
		elseif subclassA ~= subclassB then
			return subclassA < subclassB
		elseif qualityA ~= qualityB then
			return qualityA > qualityB
		elseif levelA ~= levelB then
			return levelA > levelB
		else
			return nameA < nameB
		end
	end,

	byName = function(idA, idB)
		return GetItemInfo(idA) < GetItemInfo(idB)
	end,

	byQualityAndLevel = function(idA, idB)
		local nameA, _, qualityA, levelA = GetItemInfo(idA)
		local nameB, _, qualityB, levelB = GetItemInfo(idB)
		if qualityA ~= qualityB then
			return qualityA > qualityB
		elseif levelA ~= levelB then
			return levelA > levelB
		else
			return nameA < nameB
		end
	end,

}

local currentSortingFunc = sortingFuncs.default

local itemCompareCache = setmetatable({}, {
	__index = function(t, key)
		local result = currentSortingFunc(strsplit(':', key, 2))
		t[key] = result
		return result
	end
})

function addon:SetSortingOrder(order)
	local func = sortingFuncs[order]
	if func and func ~= currentSortingFunc then
		self:Debug('SetSortingOrder', order, func)
		currentSortingFunc = func
		wipe(itemCompareCache)
		self:SendMessage('AdiBags_FiltersChanged')
	end
end

local strformat = string.format

local function CompareButtons(a, b)
	local idA, idB = a:GetItemId(), b:GetItemId()
	if idA and idB then
		if idA ~= idB then
			return itemCompareCache[strformat("%d:%d", idA, idB)]
		else
			return a:GetCount() > b:GetCount()
		end
	elseif not idA and not idB then
		local famA, famB = a:GetBagFamily(), b:GetBagFamily()
		if famA and famB and famA ~= famB then
			return famA < famB
		end
	end
	return (idA and 1 or 0) > (idB and 1 or 0)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function sectionProto:PutButtonAt(button, index)
	local oldIndex = self.slots[button]
	if index == oldIndex then return end
	self.slots[button] = index
	if index then
		if index <= self.total then
			self.freeSlots[index] = nil
			if not self.dirtyLayout then
				local row, col = math.floor((index-1) / self.width), (index-1) % self.width
				button:SetPoint("TOPLEFT", self, "TOPLEFT", col * SLOT_OFFSET, - HEADER_SIZE - row * SLOT_OFFSET)
				button:Show()
			end
		else
			self.dirtyLayout = true
		end
	end
	if oldIndex and oldIndex <= self.total then
		self.freeSlots[oldIndex] = true
	end
end

function sectionProto:SetSize(width, height)
	if self.width == width and self.height == height then return end
	self:Debug('Setting size to ', width, height)
	self.width = width
	self.height = height
	self.total = width * height

	self:SetWidth(ITEM_SIZE * width + ITEM_SPACING * math.max(width - 1 ,0))
	self:SetHeight(HEADER_SIZE + ITEM_SIZE * height + ITEM_SPACING * math.max(height - 1, 0))
	self.dirtyLayout = true
end

local buttonOrder = {}
function sectionProto:LayoutButtons(forceLayout)
	if self.count == 0 then
		return false
	elseif not forceLayout and not self.dirtyLayout then
		return true
	end
	self:Debug('LayoutButtons', forceLayout)

	local width = math.min(self.count, addon.db.profile.multiColumn and addon.db.profile.multiColumnWidth or addon.db.profile.columns)
	local height = math.ceil(self.count / math.max(width, 1))
	self:SetSize(width, height)

	wipe(self.freeSlots)
	wipe(self.slots)
	for index = 1, self.total do
		self.freeSlots[index] = true
	end

	for button in pairs(self.buttons) do
		tinsert(buttonOrder, button)
	end
	table.sort(buttonOrder, CompareButtons)

	self.dirtyLayout = false
	for index, button in ipairs(buttonOrder) do
		self:PutButtonAt(button, index)
	end

	wipe(buttonOrder)
	return true
end
