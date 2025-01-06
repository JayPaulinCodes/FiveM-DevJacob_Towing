TowTruck = {
    ACTION = {
        NONE = 0,
        LOWERING = 1,
        RAISING = 2,
    },
    CONTROL_MODE = {
        BED = -1,
        WINCH = 0,
    },
    TYPE = {
        PROP_BASED = 0,
        SCOOP_BASED = 1,
    },
}
TowTruck.__index = TowTruck

function TowTruck.new(truckConfig, truckHandle)
    local truckType = TowTruck.ParseType(truckConfig.truckType)

    if truckType == TowTruck.TYPE.PROP_BASED then
        return PropTowTruck.new(truckConfig, truckHandle)
    end

    if truckType == TowTruck.TYPE.SCOOP_BASED then
        return ScoopTowTruck.new(truckConfig, truckHandle)
    end

    return nil
end

function TowTruck.ParseType(truckType)
    local _type = type(truckType)

    if (_type == "string" and truckType:lower() == "prop")
        or (_type == "number" and truckType == TowTruck.TYPE.PROP_BASED) then
        return TowTruck.TYPE.PROP_BASED
    end

    if (_type == "string" and truckType:lower() == "scoop")
        or (_type == "number" and truckType == TowTruck.TYPE.SCOOP_BASED) then
        return TowTruck.TYPE.SCOOP_BASED
    end

    return nil
end

