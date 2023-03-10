local categories, vehicles, vehiclesByModel, soldVehicles, cardealerVehicles, rentedVehicles = {}, {}, {}, {}, {}, {}

local function GetCategories()
	categories = MySQL.query.await('SELECT * FROM vehicle_categories')
	GlobalState.vehicleShop.categories = categories

	return true
end

local function GetVehicles()
	vehicles = MySQL.query.await('SELECT vehicles.*, vehicle_categories.label AS categoryLabel FROM vehicles JOIN vehicle_categories ON vehicles.category = vehicle_categories.name')
	
	for _, vehicle in pairs(vehicles) do
		vehiclesByModel[vehicle.model] = vehicle
	end
	
	GlobalState.vehicleShop.vehicles = vehicles
	GlobalState.vehicleShop.vehiclesByModel = vehiclesByModel
	
	return true
end

local function GetSoldVehicles()
	soldVehicles = MySQL.query.await('SELECT client, model, plate, soldby, date FROM vehicle_sold ORDER BY DATE DESC')
	GlobalState.vehicleShop.soldVehicles = soldVehicles
	
	return true
end

local function GetCardealerVehicles()
	cardealerVehicles = MySQL.query.await('SELECT id, price, vehicle FROM cardealer_vehicles ORDER BY vehicle ASC')
	GlobalState.vehicleShop.cardealerVehicles = cardealerVehicles
	
	return true
end

local function GetRentedVehicles()
	MySQL.query('SELECT * FROM rented_vehicles ORDER BY player_name ASC', function(result)
		rentedVehicles = {}

		for i = 1, #result do
			local vehicle = result[i]
			rentedVehicles[#rentedVehicles + 1] = {
				name = vehicle.vehicle,
				plate = vehicle.plate,
				playerName = vehicle.player_name
			}
		end
		GlobalState.vehicleShop.rentedVehicles = rentedVehicles
			
		return true
	end)
end

CreateThread(function()
	exports["esx_society"]:registerSociety('cardealer', TranslateCap('car_dealer'), 'society_cardealer', 'society_cardealer', 'society_cardealer', {type = 'private'})
		
	GetCategories()
	GetVehicles()
	GetSoldVehicles()
	GetCardealerVehicles()
	GetRentedVehicles()
	
	local char = Config.PlateLetters
	char = char + Config.PlateNumbers
	if Config.PlateUseSpace then char = char + 1 end

	if char > 8 then
		print(('[^3WARNING^7] Character Limit Exceeded, ^5%s/8^7!'):format(char))
	end
end)

function RemoveOwnedVehicle(plate)
	MySQL.update('DELETE FROM owned_vehicles WHERE plate = ?', {plate})
end

local function getVehicleFromModel(model)
	return vehiclesByModel[model]
end

RegisterNetEvent('esx_vehicleshop:setVehicleOwnedPlayerId')
AddEventHandler('esx_vehicleshop:setVehicleOwnedPlayerId', function(playerId, vehicleProps, model, label)
	local xPlayer, xTarget = ESX.GetPlayerFromId(source), ESX.GetPlayerFromId(playerId)

	if Player(source).state.job ~= 'cardealer' or not xTarget then
		return
	end
		
	if not model then return end

	local id = nil
		
	for i = 1, #cardealerVehicles, 1 do
		local v = cardealerVehicles[i]
		if v.vehicle == model then
			id = v.id
			local sqlDel = MySQL.update.await('DELETE FROM cardealer_vehicles WHERE id = ?', {v.id})
			if not sqlDel then return end
			table.remove(cardealerVehicles, i)
			GlobalState.vehicleShop.cardealerVehicles = cardealerVehicles
			break
		end
	end

	MySQL.insert('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)', {xTarget.identifier, vehicleProps.plate, json.encode(vehicleProps)}, function(id)
		xPlayer.showNotification(TranslateCap('vehicle_set_owned', vehicleProps.plate, xTarget.getName()))
		xTarget.showNotification(TranslateCap('vehicle_belongs', vehicleProps.plate))
	end)

	local sqlIns = MySQL.insert.await('INSERT INTO vehicle_sold (client, model, plate, soldby, date) VALUES (?, ?, ?, ?, ?)', {xTarget.getName(), label, vehicleProps.plate, xPlayer.getName(), os.date('%Y-%m-%d %H:%M')})
	if not sqlIns then return end
	table.insert(soldVehicles, {xTarget.getName(), label, vehicleProps.plate, xPlayer.getName(), os.date('%Y-%m-%d %H:%M')})
	GlobalState.vehicleShop.soldVehicles = soldVehicles
end)

RegisterNetEvent('esx_vehicleshop:rentVehicle')
AddEventHandler('esx_vehicleshop:rentVehicle', function(vehicle, plate, rentPrice, playerId)
	local xPlayer, xTarget = ESX.GetPlayerFromId(source), ESX.GetPlayerFromId(playerId)

	if Player(source).state.job ~= 'cardealer' or not xTarget then
		return
	end
		
	if not vehicle or not plate or not rentPrice then return end
		
	local id = nil
	local price = nil
		
	for i = 1, #cardealerVehicles, 1 do
		local v = cardealerVehicles[i]
		if v.vehicle == vehicle then
			id = v.id
			price = v.price
			local sqlDel = MySQL.update.await('DELETE FROM cardealer_vehicles WHERE id = ?', {v.id})
			if not sqlDel then return end
			table.remove(cardealerVehicles, i)
			GlobalState.vehicleShop.cardealerVehicles = cardealerVehicles
			break
		end
	end
		
	if not price then return end

	MySQL.insert('INSERT INTO rented_vehicles (vehicle, plate, player_name, base_price, rent_price, owner) VALUES (?, ?, ?, ?, ?, ?)', {vehicle, plate, xTarget.getName(), price, rentPrice, xTarget.identifier},
	function(id)
		xPlayer.showNotification(TranslateCap('vehicle_set_rented', plate, xTarget.getName()))
	end)
end)

RegisterNetEvent('esx_vehicleshop:getStockItem')
AddEventHandler('esx_vehicleshop:getStockItem', function(itemName, count)
	local source = source
	local xPlayer = ESX.GetPlayerFromId(source)

	TriggerEvent('esx_addoninventory:getSharedInventory', 'society_cardealer', function(inventory)
		local item = inventory.getItem(itemName)

		-- is there enough in the society?
		if count > 0 and item.count >= count then

			-- can the player carry the said amount of x item?
			if not xPlayer.canCarryItem(itemName, count) then
				return xPlayer.showNotification(TranslateCap('player_cannot_hold'))
			end
			inventory.removeItem(itemName, count)
			xPlayer.addInventoryItem(itemName, count)
			xPlayer.showNotification(TranslateCap('have_withdrawn', count, item.label))
		else
			xPlayer.showNotification(TranslateCap('not_enough_in_society'))
		end
	end)
end)

RegisterNetEvent('esx_vehicleshop:putStockItems')
AddEventHandler('esx_vehicleshop:putStockItems', function(itemName, count)
	local source = source
	local xPlayer = ESX.GetPlayerFromId(source)

	TriggerEvent('esx_addoninventory:getSharedInventory', 'society_cardealer', function(inventory)
		local item = inventory.getItem(itemName)

		if item.count < 0 then
			xPlayer.showNotification(TranslateCap('invalid_amount'))
			return
		end
				
		xPlayer.removeInventoryItem(itemName, count)
		inventory.addItem(itemName, count)
		xPlayer.showNotification(TranslateCap('have_deposited', count, item.label))
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop:buyVehicle', function(source, cb, model, plate)
	local xPlayer = ESX.GetPlayerFromId(source)
	local modelPrice = getVehicleFromModel(model).price

	if not modelPrice then
		cb(false) 
		return 
	end
		
	if xPlayer.getMoney() < modelPrice then
		cb(false)
		return 
	end

	xPlayer.removeMoney(modelPrice, "Vehicle Purchase")

	MySQL.insert('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)', {xPlayer.identifier, plate, json.encode({model = joaat(model), plate = plate})
	}, function(rowsChanged)
		xPlayer.showNotification(TranslateCap('vehicle_belongs', plate))
		ESX.OneSync.SpawnVehicle(joaat(model), Config.Zones.ShopOutside.Pos, Config.Zones.ShopOutside.Heading,{plate = plate}, function(vehicle)
			Wait(100)
			local vehicle = NetworkGetEntityFromNetworkId(vehicle)
			Wait(300)
			TaskWarpPedIntoVehicle(GetPlayerPed(source), vehicle, -1)
		end)
		cb(true)
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop:buyCarDealerVehicle', function(source, cb, model)
	local xPlayer = ESX.GetPlayerFromId(source)

	if Player(source).state.job ~= 'cardealer' then
		return cb(false)
	end
		
	local modelPrice = getVehicleFromModel(model).price

	if not modelPrice then
		return cb(false)
	end
		
	TriggerEvent('esx_addonaccount:getSharedAccount', 'society_cardealer', function(account)
		if account.money < modelPrice then
			return cb(false)
		end

		MySQL.insert('INSERT INTO cardealer_vehicles (vehicle, price) VALUES (?, ?)', {model, modelPrice},
		function(rowsChanged)
			if not rowsChanged then 
				cb(false)
				return
			end
			account.removeMoney(modelPrice)
			GetCardealerVehicles()
			cb(true)
		end)
	end)
end)

RegisterNetEvent('esx_vehicleshop:returnProvider')
AddEventHandler('esx_vehicleshop:returnProvider', function(vehicleModel)
	local xPlayer = ESX.GetPlayerFromId(source)

	if Player(source).state.job ~= 'cardealer' then
		return
	end
		
	local id = nil
	local price = nil
		
	for i = 1, #cardealerVehicles, 1 do
		local v = cardealerVehicles[i]
		if v.vehicle == vehicleModel then
			id = v.id
			price = v.price
			local sqlDel = MySQL.update.await('DELETE FROM cardealer_vehicles WHERE id = ?', {v.id})
			if not sqlDel then return end
			table.remove(cardealerVehicles, i)
			GlobalState.vehicleShop.cardealerVehicles = cardealerVehicles
			break
		end
	end
		
	if not id or not price then return end

	TriggerEvent('esx_addonaccount:getSharedAccount', 'society_cardealer', function(account)
		local vehPrice = ESX.Math.Round(price * 0.75)
		local vehicleLabel = getVehicleFromModel(vehicleModel).label

		account.addMoney(vehPrice)
		xPlayer.showNotification(TranslateCap('vehicle_sold_for', vehicleLabel, ESX.Math.GroupDigits(vehPrice)))
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop:giveBackVehicle', function(source, cb, plate)
	local base_price, vehicle = nil, nil
		
	if not plate then return end
		
	for i = 1, #rentedVehicles, 1 do
		local v = rentedVehicles[i]
		if v.plate = plate then
			base_price = v.base_price
			vehicle = v.vehicle
			local sqlDel = MySQL.update.await('DELETE FROM rented_vehicles WHERE plate = ?', {plate})
			if not sqlDel then return cb(false) end
			table.remove(rentedVehicles, i)
			GlobalState.vehicleShop.rentedVehicles = rentedVehicles
			break
		end
	end

	local sqlIns = MySQL.insert.await('INSERT INTO cardealer_vehicles (vehicle, price) VALUES (?, ?)', {vehicle, base_price})
	if not sqlIns then return cb(false) end 
	GetCardealerVehicles()

	RemoveOwnedVehicle(plate)
	cb(true)
end)

ESX.RegisterServerCallback('esx_vehicleshop:resellVehicle', function(source, cb, plate, model)
	local xPlayer, resellPrice = ESX.GetPlayerFromId(source)

	if Player(source).state.job == 'cardealer' or not Config.EnablePlayerManagement then
		-- calculate the resell price
		for i=1, #vehicles, 1 do
			if joaat(vehicles[i].model) == model then
				resellPrice = ESX.Math.Round(vehicles[i].price / 100 * Config.ResellPercentage)
				break
			end
		end

		if not resellPrice then
			print(('[^3WARNING^7] Player ^5%s^7 Attempted To Resell Invalid Vehicle - ^5%s^7!'):format(source, model))
			return cb(false)
		end
		for i = 1, #rentedVehicles, 1 do
			if rentedVehicles[i].plate == plate then
				cb(false)
				return
			end
		end
		MySQL.single('SELECT * FROM owned_vehicles WHERE owner = ? AND plate = ?', {xPlayer.identifier, plate},
		function(result)
			if not result then
				return cb(false)
			end
			local vehicle = json.decode(result.vehicle)

			if vehicle.model ~= model then
				print(('[^3WARNING^7] Player ^5%s^7 Attempted To Resell Vehicle With Invalid Model - ^5%s^7!'):format(source, model))
				return cb(false)
			end
			if vehicle.plate ~= plate then
				print(('[^3WARNING^7] Player ^5%s^7 Attempted To Resell Vehicle With Invalid Plate - ^5%s^7!'):format(source, plate))
				return cb(false)
			end

			xPlayer.addMoney(resellPrice, "Sold Vehicle")
			RemoveOwnedVehicle(plate)
			cb(true)
		end)
	end
end)

ESX.RegisterServerCallback('esx_vehicleshop:getStockItems', function(source, cb)
	TriggerEvent('esx_addoninventory:getSharedInventory', 'society_cardealer', function(inventory)
		cb(inventory.items)
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop:getPlayerInventory', function(source, cb)
	local xPlayer = ESX.GetPlayerFromId(source)
	local items = xPlayer.inventory

	cb({items = items})
end)

ESX.RegisterServerCallback('esx_vehicleshop:isPlateTaken', function(source, cb, plate)
	MySQL.scalar('SELECT plate FROM owned_vehicles WHERE plate = ?', {plate},
	function(result)
		cb(result ~= nil)
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop:retrieveJobVehicles', function(source, cb, type)
	local xPlayer = ESX.GetPlayerFromId(source)

	MySQL.query('SELECT * FROM owned_vehicles WHERE owner = ? AND type = ? AND job = ?', {xPlayer.identifier, type, xPlayer.job.name},
	function(result)
		cb(result)
	end)
end)

RegisterNetEvent('esx_vehicleshop:setJobVehicleState')
AddEventHandler('esx_vehicleshop:setJobVehicleState', function(plate, state)
	MySQL.update('UPDATE owned_vehicles SET `stored` = ? WHERE plate = ? AND job = ?', {state, plate, Player(source).state.job},
	function(rowsChanged)
		if rowsChanged == 0 then
			print(('[^3WARNING^7] Player ^5%s^7 Attempted To Exploit the Garage!'):format(source, plate))
		end
	end)
end)

function PayRent()
	local timeStart = os.clock()
	print('[^2INFO^7] ^5Rent Payments^7 Initiated')

	MySQL.query('SELECT rented_vehicles.owner, rented_vehicles.rent_price, rented_vehicles.plate, users.accounts FROM rented_vehicles LEFT JOIN users ON rented_vehicles.owner = users.identifier', {},
	function(rentals)
		local owners = {}
		for i = 1, #rentals do
			local rental = rentals[i]
			if not owners[rental.owner] then
				owners[rental.owner] = {rental}
			else
				owners[rental.owner][#owners[rental.owner] + 1] = rental
			end
		end

		local total = 0
		local unrentals = {}
		local users = {}
		for k, v in pairs(owners) do
			local sum = 0
			for i = 1, #v do
				sum = sum + v[i].rent_price
			end
			local xPlayer = ESX.GetPlayerFromIdentifier(k)

			if xPlayer then
				local bank = xPlayer.getAccount('bank').money

				if bank >= sum and #v > 1 then
					total = total + sum
					xPlayer.removeAccountMoney('bank', sum, "Vehicle Rental")
					xPlayer.showNotification(('You have paid $%s for all of your rentals'):format(ESX.Math.GroupDigits(sum)))
				else
					for i = 1, #v do
						local rental = v[i]
						if xPlayer.getAccount('bank').money >= rental.rent_price then
							total = total + rental.rent_price
							xPlayer.removeAccountMoney('bank', rental.rent_price, "Vehicle Rental")
							xPlayer.showNotification(TranslateCap('paid_rental', ESX.Math.GroupDigits(rental.rent_price), rental.plate))
						else
							xPlayer.showNotification(TranslateCap('paid_rental_evicted', ESX.Math.GroupDigits(rental.rent_price), rental.plate))
							unrentals[#unrentals + 1] = {rental.owner, rental.plate}
						end
					end
				end
			else
				local accounts = json.decode(v[1].accounts)
				if accounts.bank < sum then
					sum = 0
					local limit = false
					for i = 1, #v do
						local rental = v[i]
						if not limit then
							sum = sum + rental.rent_price
							if sum > accounts.bank then
								sum = sum - rental.rent_price
								limit = true
							end
						else
							unrentals[#unrentals + 1] = {rental.owner, rental.plate}
						end
					end
				end
				if sum > 0 then
					total = total + sum
					accounts.bank = accounts.bank - sum
					users[#users + 1] = {json.encode(accounts), k}
				end
			end
		end

		if total > 0 then
			TriggerEvent('esx_addonaccount:getSharedAccount', 'society_cardealer', function(account)
				account.addMoney(total)
			end)
		end

		if next(users) then
			MySQL.prepare.await('UPDATE users SET accounts = ? WHERE identifier = ?', users)
		end

		if next(unrentals) then
			MySQL.prepare.await('DELETE FROM rented_vehicles WHERE owner = ? AND plate = ?', unrentals)
		end
			
		GetRentedVehicles()
		print(('[^2INFO^7] ^5Rent Payments^7 took ^5%s^7 ms to execute'):format(ESX.Math.Round((os.time() - timeStart) / 1000000, 2)))
	end)
end

TriggerEvent('cron:runAt', 22, 00, PayRent)
