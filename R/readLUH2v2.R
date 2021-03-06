#' @title readLUH2v2
#' @description read LUH inputs
#' 
#' @param subtype switch between different inputs
#' 
#' @return List of magpie objects with results on cellular level, weight, unit and description.
#' @author Florian Humpenoeder, Stephen Wirth, Kristine Karstens, Felicitas Beier, Jan Philipp Dietrich
#'
#' @importFrom ncdf4 nc_open
#' @importFrom raster raster extent brick subset aggregate projectRaster extent<- as.matrix extract
#' @importFrom parallel detectCores makeCluster stopCluster
#' @importFrom doParallel registerDoParallel
#' @importFrom foreach foreach %dopar%
#' @importFrom magclass as.magpie mbind
#' @importFrom madrat getConfig

readLUH2v2 <- function(subtype) {

  # basic settings  
  time_sel   <- seq(1900,2015,by=1)
  offset     <- 849  #year 850=1, year 1900=1051, year 2015=1166
  # limit no_cores to max 2 to avoid out of memory errors caused
  # by to many runs in parallel
  no_cores   <-  min(getConfig("nocores"),2)
  
  #File to process
  f_states <- "states.nc"
  f_man    <- "management.nc"
  
  ### Define dimensions
  if (grepl("_lpjcell", subtype)){
    ncells    <- 67420
    map       <- toolGetMapping("LPJ_CellBelongingsToCountries.csv",type="cell")
    cellNames <- paste(map$ISO,1:ncells,sep=".")
    map       <- map[c("lon","lat")]
  } else {
    ncells    <- 59199
    map       <- as.data.frame(magpie_coord)
    cellNames <-toolMappingFile(type="cell",name="CountryToCellMapping.csv",readcsv=TRUE)$celliso
  }

  if(grepl("states", subtype)){
    
    #Open file and process information
    nc_file <- nc_open(f_states)
    data <- setdiff(names(nc_file$var),c("secma","secmb","lat_bounds","lon_bounds"))

    #Land area
    carea <- raster("staticData_quarterdeg.nc",varname="carea")
    extent(carea) <- c(-180,180,-90,90)

    #Parallelization
    cl       <- makeCluster(no_cores,outfile="par_debug.txt")
    registerDoParallel(cl)

    #Do the stuff
    data_sel <- NULL
    x <- foreach(data_sel=1:length(data)) %dopar% {
        message(data[data_sel])
        shr <- subset(brick(f_states,varname=data[data_sel]),time_sel-offset)
        x <- aggregate(shr*carea,fact=2,fun=sum)
        mag <- as.magpie(extract(x,map),spatial=1,temporal=2)
        getNames(mag) <- data[data_sel]
        getCells(mag) <- cellNames
        getYears(mag) <- time_sel
        return(mag)
      }
    stopCluster(cl)
    gc()
    
    x <- mbind(x)

    #Convert from km^2 to Mha
    x <- x/10000
    x[is.na(x)] <- 0

  } else if (grepl("irrigation", subtype)) {

    #Mapping between states and management_irrigation
    data_man    <- c("irrig_c3ann","irrig_c3per","irrig_c4ann","irrig_c4per","irrig_c3nfx","flood")
    data_states <- c("c3ann","c3per","c4ann","c4per","c3nfx","c3ann")
    data        <- matrix(data=c(data_man,data_states),ncol=2)

    #Land area
    carea         <- raster("staticData_quarterdeg.nc",varname="carea")
    extent(carea) <- c(-180,180,-90,90)
    
    #Parallelization
    cl <- makeCluster(no_cores,outfile="par_debug.txt")
    registerDoParallel(cl)

    #Do the stuff
    x <- foreach(data_sel=1:length(data_man)) %dopar% {
        message(data[data_sel,1])
        shr    <- subset(brick(f_states,varname=data[data_sel,2]),time_sel-offset)
        ir_shr <- subset(brick(f_man,varname=data[data_sel,1]),time_sel-offset)
        
        #grid cell fraction of crop area x grid cell area x irrigated fraction of crop area
        x <- aggregate(shr*carea*ir_shr,fact=2,fun=sum)
        
        mag <- as.magpie(extract(x,map),spatial=1,temporal=2)
        getNames(mag) <- data[data_sel,1]
        getYears(mag) <- time_sel
        getCells(mag) <- cellNames
        return(mag)
      }
    stopCluster(cl)
    gc()
    x <- mbind(x)

    #Convert from km^2 to Mha
    x <- x/10000
    x[is.na(x)] <- 0

  } else if (grepl("ccode", subtype)) {

    #Load raster data on 0.25° and extend to full grid
    ccode25         <- raster("staticData_quarterdeg.nc",varname="ccode")
    extent(ccode25) <- c(-180,180,-90,90)

    #Create new raster object on 0.5° and re-project 0.25°-raster on 0.5°-raster
    r50     <- raster(res=0.5)
    ccode50 <- projectRaster(ccode25,r50,over=TRUE, method="ngb") #re-project to regular grid
    
    x <- as.magpie(extract(ccode50,map),spatial=1)
    getYears(x) <- 2000
    getNames(x) <- "ccode"
    getCells(x) <- cellNames
    getSets(x) <- c("country.cell","t","ccode")
  }
  return(clean_magpie(x))
}

