-- This Lua file loads the various local versions of the job.load / job.save
-- registrations. 

-- We make the very commonly used functions global

allocate   = utilities.storage.allocate
checked    = utilities.storage.checked
lpegmatch  = lpeg.match

format = string.format

sort              = table.sort
sortedhash        = table.sortedhash
sortedkeys        = table.sortedkeys
setmetatableindex = table.setmetatableindex
serialize         = table.serialize
tInsert           = table.insert

report_passes  = logs.reporter("job","passes")
definetable    = utilities.tables.definetable
accesstable    = utilities.tables.accesstable
packers        = utilities.packers

-- provide the bare minimum of the core-uti.lua module for our needs

job = { }

savelist = { }

function job.register(collected, tobesaved, initializer, finalizer, serializer)
    savelist[#savelist+1] = { collected, tobesaved, initializer, finalizer, serializer }
end

function job.save(subDocName) -- we could return a table but it can get pretty large
  local filename = subDocName.."-parallel.tuc"
  local f = io.open(filename,'w')
  if f then
    f:write("local utilitydata = { }\n")
    for l=1,#savelist do
      local list       = savelist[l]
      local target     = list[1]
      local uTarget     = format("utilitydata.%s", target)
      local data       = list[2]
      local finalizer  = list[4]
      local serializer = list[5]
      if type(finalizer) == "function" then
        finalizer(subDocName, target)
      end
      if type(data) == "string" then
        data = pContextData[data]
      end
      if job.pack then
        packers.pack(data,jobpacker,true)
      end
      local definer, name = definetable(uTarget,true,true) -- no first and no last
      if serializer then
        f:write(definer,"\n\n",serializer(data,name,true),"\n\n")
      else
        f:write(definer,"\n\n",serialize(data,name,true),"\n\n")
      end
    end
    if job.pack then
      packers.strip(jobpacker)
      f:write(serialize(jobpacker,"utilitydata.job.packed",true),"\n\n")
    end
    f:write("return utilitydata")
    f:close()
  end
end

-- WHY is the TUC file version corrupted?!?!?
-- it seems to be a conflict between decimal and hexadeciman storage of floats
--
local function load(filename)
    if lfs.isfile(filename) then

        local function dofile(filename)
            local result = loadstring(io.loaddata(filename))
            if result then
                return result()
            else
                return nil
            end
        end

        local okay, data = pcall(dofile,filename)
        if okay and type(data) == "table" then
--            local jobversion  = job.version
--            local datacomment = data.comment
--            local dataversion = datacomment and datacomment.version or "?"
--            if dataversion ~= jobversion then
--                report_passes("version mismatch: %s <> %s",dataversion,jobversion)
--            else
                return data
--            end
--        else
--            os.remove(filename) -- probably a bad file (or luajit overflow as it cannot handle large tables well)
--            report_passes("removing stale job data file %a, restart job, message: %s%s",filename,tostring(data),
--                jit and " (try luatex instead of luajittex)" or "")
--            os.exit(true) -- trigger second run
        end
    end
end

function job.loadData(subDocName, filename)
  pContextTUCData[subDocName] = pContextTUCData[subDocName] or { }
  pTUCData = pContextTUCData[subDocName]
  if not filename then
    filename = subDocName.."-parallel.tuc"
  end
  local utilitydata = load(filename)
  if utilitydata then
    local jobpacker = utilitydata.job.packed
    for i=1,#savelist do
      local list        = savelist[i]
      local target      = list[1]
      local result      = accesstable(target,utilitydata)
      if result then
        local done = packers.unpack(result,jobpacker,true)
        if done then
          pTUCData[target] = result
        else
          report_passes("pack version mismatch")
        end
      end
    end
  end
end

function job.handleData(subDocName)
  for i=1,#savelist do
    local list        = savelist[i]
    local target      = list[1]
    local initializer = list[3]
    if type(initializer) == "function" then
      initializer(subDocName, target)
    end
  end
end

-- Provide a global function to report differences in TUC objects

function reportObject(anObj, message)
  if tyep(anObj) == "table" then
    print(message.." is a table")
  else
    print(message.." ["..to_string(anObj).."]")
  end
end

function reportIfObjectsAreDifferent(mainObj, otherObj, subDocName, curPath)
  if mainObj == otherObj then return end
  
  if type(mainObj) ~= "table" or type(otherObj) ~= "table" then
    print("Objects are different at ["..curPath.."] in "..subDocName)
    reportObject(mainObj,  " mainObj: ")
    reportObject(otherObj, "otherObj: ")
    return
  end
  
  for key, value in pairs(otherObj) do
    reportIfObjectsAreDifferent(mainObject[key], otherObj[key], subDocName, curPath..'.'..key)
  end
end

-- Now load the local job.load registration files

-- Order of registration can be found in the `context.mkxl` file

--   -------- (comment)            (this is used to ensure comments are saved)
--   core-uti (job.variables)
--   file-job (job.structure)
--   anch-pos (job.positions)
--   core-two (job.passes)
--   core-dat (job.datasets & job.pagestates)
--   strc-ini (structures.specials)
--   strc-doc (structures.sections)
--   strc-num (structures.counters)
--   strc-lst (structures.lists)
--   strc-pag (structures.pages)
--   strc-ref (structures.references)
--   strc-reg (structures.registers)
--   pack-obj (job.objects)
--   strc-syn (structures.synonyms)
--   strc-blk (structures.blocks)
--   grph-fil (job.files)             (called by grph-inc)
--   publ-ini (publications)
--   lpdf-epa (job.embedded)          (called by back-pdf)
--   lpdf-wid (job.fileobjreferences) (called by back-pdf)

local registrationFiles = {
  'comment',
  'job.variables.checksums',
  'job.variables.collected',
  'job.structure.collected',
  -- NOTE: in Context structures.pages
  --       is AFTER structures.list.ordered
  --       and BEFORE structures.references.collected
  --       but it is required by job.positions.collected
  'structures.pages.collected',
  'job.positions.collected',
  -- depends on structures.pages
  --   via the pContextStructData.subDocs.*.firstPage
  'job.passes.collected',  -- needs work
  'job.datasets.collected',
  'job.pagestates.collected',
  -- depends on structures.pages
  --   via the pContextStructData.subDocs.*.firstPage
  'structures.specials.collected',
  'structures.sections.collected',
  'structures.counters.collected',
  'structures.lists.collected',
  'structures.references.collected', -- needs work ;-(
  -- depends on structures.pages
  --   via the pContextStructData.subDocs.*.firstPage
  -- CREATES GLOBAL: structures_references_internal
  'structures.references.referred', -- needs work ;-(
  -- synthesized from structures_references_internal
  'structures.registers.collected', 
  'job.objects.collected',
  'structures.synonyms.collected',
  'structures.blocks.collected',
  'job.files.collected',
  'publications.collected',
  'job.embedded.collected',
  'job.fileobjreferences.collected',
}

for i, regFile in ipairs(registrationFiles) do
  print("starting to load    "..regFile)
  dofile(tpcontextDir..'/pContextData/'..regFile)
  print("finished    loading "..regFile)
end
