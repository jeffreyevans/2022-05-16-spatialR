---
source: Rmd
title: "spatialR workshop  session 2 - Spatial data query, manipulation, topology operators, raster analysis and landscape structure"
author:
  - Jeffrey S. Evans^[The Nature Conservancy, jeffrey_evans@tnc.org] 
date: "5/17/2022"
output:
  html_document: 
    toc: yes
    keep_md: yes
    code_folding: hide
---

**Objectives**

One seemingly limiting factor to full migration of spatial analysis in R is ability to implement basic GIS functions. We will cover various vector overlay procedures with a focus specifically on spatial data analysis, starting with data manipulation, query and overlay. We will also cover distance and proximity analysis thus, providing a foundation to topics covered later in the workshop (e.g., assessing spatial autocorrelation, network analysis). We will also cover basic raster analysis including single raster operators, overlay and focal functions. Finally, we will introduce concepts of quantifying landscape structure using landscape metrics.  

# Setup

## Add required libraries and set working environment


```{.r .fold-show}
invisible(lapply(c("sp", "terra", "spdep", "spatialEco", "sf", "terra", 
      "raster", "spatstat", "spatstat.geom", "dplyr", "devtools",
	    "landscapemetrics"), require, character.only=TRUE))

# set your working and data directories here
setwd("C:/spatialR/session02") 
  data.dir <- file.path(getwd(), "data")
```

# 2.1 - Vector analysis 

## Read data

Read "plots.shp" and "soil.shp" in as sf objects. Plot resulting objects. 

|    See; st_read, plot, st_geometry  


```r
# Read data 
plots <- st_read(file.path(data.dir, "plots.shp"))
  soil <- st_read(file.path(data.dir, "soil.shp"))

plot(st_geometry(soil))
  points(st_coordinates(plots), pch=20, col="red")
  # plot(st_geometry(plots), pch=20, col="red", add=TRUE)
```
    
## Buffer points

Buffer the plots data to 200m 

|    See; st_buffer 
 

```r
plots.buff <- st_buffer(plots, dist=200)
  plot(st_geometry(plots.buff))
    plot(st_geometry(plots), pch=20, add=TRUE)
```
    
## Clip polygons 

Intersect (clip) soil with buffers and relate back to points. 

|    See; gIntersection and intersect) 


```r
plots.soil <- st_intersection(plots.buff, soil) 
  plot(st_geometry(plots.soil))
```

## Calculate spatial area fractions

Calculate soil-type ("musym" attribute) area proportion for each plot. 

|    See; table, prop.table	


```r
# Pull unique soil types
( stype = sort(unique(plots.soil$musym)) )

# Note; polygons are non-sequential eg., 
which(plots.soil$ID == 25)

# get area for each polygon		
plots.soil$soil.area <- as.numeric(st_area(plots.soil))

# loop through each polygon and get proportion(s)
soil.pct <- list()
  for(i in unique(plots.soil$ID) ) {
    s <- plots.soil[plots.soil$ID == i ,]
	  ta <- sum(s$soil.area)
	    spct <- tapply(s$soil.area, s$musym, function(x) sum(x) / ta)  
	    scts <- table(factor(s$musym, levels=stype))
	  scts[which(names(scts) %in% names(spct))] <- round(spct,4)
    soil.pct[[i]] <- scts
    }
soil.pct <- data.frame(ID=unique(plots.soil$ID), do.call(rbind, soil.pct))
  plots <- merge(plots, soil.pct, by="ID")
    plot(plots["GpD"], pch=20, cex=2)
  
#### or, alternately using lapply as loop (AKA the R way)  
p <- lapply(unique(plots.soil$ID), function(i) {
  s <- plots.soil[plots.soil$ID == i ,]
    ta <- sum(s$soil.area)
	round(tapply(s$soil.area, s$musym, function(x) sum(x) / ta),4)  
})
  p <- plyr::ldply(p, rbind)
    p[is.na(p)] <- round(0,4)
      str(p)
```

## Point in polygon

Point in polygon analysis to relate soil attributes to plots. 

|    See; point.in.poly  


```r
# Point in polygon (relate soil attributes to points)
soil.plots <- sf::st_intersection(plots, soil)
  head(soil)
  head(plots)  
  head(soil.plots)
```
  
## Spatial aggregation (dissolve)

Dissolve polygons using "NWBIR74" column, create column where < median is 0 else 1 then dissolve features by this column and plot     


```r
# read data from sf package
polys <- st_read(system.file("shape/nc.shp", package="sf"))
  polys$p <- ifelse(polys$NWBIR74 < quantile(polys$NWBIR74, p=0.5), 0 ,1)
   
# sf approach  
diss <- polys %>% 
  dplyr::group_by(p) %>% 
    summarise(m = max(p)) %>% 
      st_cast()
plot(diss["p"])
```

## Spatial aggregation (zonal)

Work through this zonal function that calculates the proportion of covertypes around the periphery of each polygon and then calculates  Isolation by Distance (IBD). Please take the time to examine the output objects of each step, plot intermediate results and dissect the peripheral.zonal function. Please note; when you dissect a for loop you need to define the iterator so, in this case if it is defined (eg., j=1) then you can run the inside of the loop (omitting the for line and the end curly bracket. Don’t forget, to run the function you need to copy-and-paste the whole thing into R to "source" it.   
 

```r
# Read shapefile "wetlands" and raster "landtype.tif" in data.dir
( wetlands <- st_read(file.path(data.dir, "wetlands.shp")) )
  ( wetlands <- wetlands[sample(1:nrow(wetlands),10),] )

plot(st_geometry(wetlands))

# Landcover classes
# 3-Barren, 4-regeneration, 5-forest, 10-Riparian, 11-urban, 
# 12-pasture, 13-weedy grasses, 15-crops, 19-water

lcov <- rast(file.path(data.dir, "landtype.tif") )

# Syntax for erasing a polygon, follows idea of inverse 
# focal function  
p <- st_buffer(wetlands[1,], dist=1000)
  p <- st_difference(p, st_union(wetlands[1,]))	   			   
    plot(mask(crop(lcov, ext(p)),vect(p)))

# Define classes and class names
( classes <- sort(unique(lcov[])) )
lcnames <- c("barren", "regen", "forest", "riparian",   
             "urban", "pasture", "grasses",  "crops", 
			       "water")

pzonal <- function(x, y, d = 1000, classes = NULL, 
                   class.names = NULL) {
  if(is.null(classes)) {
    classes <- sort(unique(y[]))
  }
  if(!is.null(class.names)) 
    names(classes) <- class.names
    suppressWarnings({
	  p <- st_buffer(x, dist=1000)
	  p <- st_difference(p, st_union(x))
	})  
	r <- extract(y, vect(p))
	  r <- lapply(unique(r$ID), function(j) {
	    prop.table(table(factor(r[r$ID==j,][,2],
		levels=classes)))})
  r <- as.data.frame(do.call(rbind, r))
    if(!is.null(class.names)) 
	  names(r) <- class.names
  return(r)
}

# Calculate peripheral zonal statistics
( class.prop <- pzonal(x=wetlands, y=lcov, d = 1000,
                      class.names=lcnames) ) 
 
# check global class proportions (column sums)
apply(class.prop, MARGIN=2, sum)
 
# Isolation by Distance (IBD) 
( d <- as.matrix(st_distance(wetlands) ))	 
  diag(d) <- NA
    d <- apply(d, MARGIN=1, FUN=function(x) min(x, na.rm=TRUE))
      d <- d / max(d)

# add proportion and IBD results to polygons
wetlands$ibd <- d
wetlands <- merge(wetlands, data.frame(ID=wetlands$ID, class.prop), by="ID")

# Plot some landcover proportions
plot(wetlands["crops"])
plot(wetlands["grasses"])
plot(wetlands["pasture"])

# Plot IBD
plot(wetlands["ibd"])

# Define class breaks, cut, create color vector and pass to plot
l <- cut(wetlands$ibd, classBreaks(wetlands$ibd, n=3, 
         type = "geometric"), include.lowest = TRUE,
		 labels=c("low", "med", "high"))

# color vector
my.col <- l
  levels(my.col) <- c("blue", "orange", "red")

# Plot results 
plot(st_geometry(wetlands), col=as.character(my.col), border = NA)
  box()
  legend("bottomleft", legend=levels(l), 
         fill=levels(my.col))  
```

# 2.2 Raster data analysis

## Read raster data (single band and multi band)

Read bands 1 and 5 from from "ppt2000.tif" as single band objects,  all bands from  "ppt2000.tif" and "ppt2001.tif" (2 single band and 2 multi band objects).


```r
ppt.jan <- rast(file.path(data.dir, "ppt2000.tif"), lyrs=1) 
ppt.may <- rast(file.path(data.dir, "ppt2000.tif"), lyrs=5)
ppt.2000 <- rast(file.path(data.dir, "ppt2000.tif")) 
ppt.2001 <- rast(file.path(data.dir, "ppt2001.tif"))
```

## Global raster statistics

Calculate summary statistics (global) for mean, sd and bakers choice. 

|    See; global, summary


```r
# Summary statistics (global)
( rmin <- global(ppt.jan, stat="min") )
( rmax <- global(ppt.jan, stat="max") )
( rmean <- global(ppt.jan, stat="mean") )
summary(ppt.jan)
summary(ppt.jan)[5]
```

## Raster transformations 

Row standardization is a common approach in getting data on the same scale while retaining the distribution. There are numerious other transformations that can be leveraged for various reasons so, this is something to have passing familiarity with.  

Row standardize (x / max(x)) "ppt.jan" then, "ppt.jan" and "ppt.may" See; global, max and standard math operations


```r
# Row standardization
ppt.jan.std <- ppt.jan / as.numeric(global(ppt.jan, stat="max"))

# Row standardization using global max values across months
ppt.jan.std <- ppt.jan / max(global(c(ppt.jan, ppt.may), stat="max"))
  summary(ppt.jan.std)
```

## Multi-band statistics

1. Calculate mean of "ppt.jan" and "ppt.may" 

2. Calculate median for all dates in ppt.2000

3. Calculate median for growing season may-aug [[5:8]] in ppt.2000 

4. Calculate abs difference for may [5] between ppt.2000 & ppt.2001

|    See; app, lapp, mean, median


```r
# 1. Returns mean between >=2 raster
# Difference usage between direct operator, 
#   these two calls have the same result
( mean.ppt <- (ppt.jan + ppt.may) / 2 )
( mean.ppt <- app(c(ppt.jan, ppt.may), fun=mean) )

# 2. Returns median for entire raster stack
( med.2000 <- app(ppt.2000, median) )

# 3. Returns median for range in raster stack
( gs.med.2000 <- app(ppt.2000[[5:8]], median) )

# 4. Returns absolute difference between two rasters (note lapp)
adif.ppt <- lapp(c(ppt.2000[[5]], ppt.2001[[5]]), 
                    fun=function(x,y) { abs(x-y) } )

par(mfrow=c(2,2))
  plot(mean.ppt)
  plot(med.2000)
  plot(gs.med.2000)
  plot(adif.ppt)
```
  
## Multi-band functions

Calculate number of days with rain over median across all dates. 

|    See; app, median


```r
( m <- global(ppt.2000, stat=median)[,1] )

rain.fun <- function(x, p = 23.4997) {
  if( length(which(TRUE == (x %in% NA))) == length(x) )  {
	  return(NA)
    } else {
    return( length(na.omit(x[x >= p])) )
   }
 } 

rain.freq <- app(ppt.2000, fun=rain.fun, p=m) 

plot(rain.freq, main="Frequency > median precipitation 2000")  
```

## Focal statistics

A focal window is defined as a matrix where 1 represents values and 0 non-values. A uniform valued NxN window can easily be defined using: matrix(1, nrow=n, ncol=n). And, yes you can use custom values (eg., Guassian) in the matrix to perform specialized operators. For example using matrix(1/9,nrow=3,ncol=3) to decompose the focal values will return the same result as calculating mean with a uniform matrix.   

Calculate focal mean of "ppt.jan" within an 11x11 window, plot results. 

|    See; focal, matrix 


```r
ppt.mean11 <- focal(ppt.jan, w=matrix(1,nrow=11,ncol=11), fun=mean)
  par(mfrow=c(1,2)) 
    plot(ppt.mean11)
    plot(ppt.jan)
```

## Focal functions

It is possible to also write custom functions for local scale evaluation. With highly customized functions you can even calculate focal funtions on more than one raster. Honestly, the sky is the limit but, here is one example that derives the fractional deviation of the local from the global (starting to get into gradient landscape metrics). 

Calculate percent of values <= global mean within an 11x11 window/ See; focal, global, matrix 


```r
# Passing focal custom function
pct.mean <- function(x, p=22.6776) { length(x[x >= p]) / length(x) }

( p.mean = global(ppt.jan, stat="mean")[,1] )
ppt.break <- focal(ppt.jan, w=matrix(1,nrow=5,ncol=5), 
                   fun=pct.mean, p=p.mean) 
```

## Reproject raster

Reproject to UTM using "elev.tif" as reference raster. 

|    See; project, rast


```r
( elev <- rast(file.path(data.dir, "elev.tif")) )
( ppt <- rast(file.path(data.dir, "ppt_geo.tif"), lyrs=5) )

# Create a reference raster from an extent
ref <- rast(ext(elev), crs=crs(elev))
  res(ref) <- 1000 # target resolution from native DD 0.04166667 

# Reproject to UTM 
( ppt.utm <- project(ppt, ref, method="bilinear") )
						  						  
par(mfrow=c(2,1))
  plot(ppt)
  plot(ppt.utm)
```

# 2.3 - Raster/Vector integration 

## Read data

Read the "plots.shp" points and "landcover.tif" raster. See; st_read, rast


```r
plots <- st_read(file.path(data.dir, "plots.shp"))
  lc <- rast(file.path(data.dir, "landcover.tif")) 
```

## Extract raster values for points

Extract raster cell values (lc) for points (plots). Note; vector objects (ie., sf) must be terra vect class objects. 

|    See; extract and vect


```r
head( v <- extract(lc, vect(plots)) ) 
```

## Extract raster values for polygons

Buffer the plots to 200m and then extract the "lc" raster cell values. What class is the object? What is the ID column representing? How can we operate on it to get meaningful statistical summaries.   


```r
plots.buff <- st_buffer(plots, dist=200)
  ( r.vals <- extract(lc, vect(plots.buff)) )   
```

## Aggregate polygon raster values

Unlike points, that have one value per point, polygons have any number of values that intersect each given polygon. As such, the data structure is a bit different. Historically, in the raster library, results were returned as a list object necessitating the use of lapply. In the terra library, results are returned as a data.frame with an ID column indicating the polygon index. If there were 10 raster cells intersecting a polygon then that polygon index will be replicated 10 times, with the associated raster values. You can use an iterator on the ID field to aggregate these values into a desired statistic.    
Now write a function, to pass to tapply, that will calculate the proportion of value 23 and one for 41, 42 and 43. Add to data and play with plotting results. See; for, tapply, split, aggregrate  


```r
pct <- function(x, p = 23) { length( x[x == p] ) / length(x) }
  tapply(r.vals[,2], r.vals$ID, FUN=pct)
 
pct <- function(x, p) { length(which( x %in% p)) / length(x) }
  tapply(r.vals[,2], r.vals$ID, FUN=pct, p=c(41,42,43))

# Add to "plots" data
plots$pct.forest <- as.numeric(tapply(r.vals[,2], r.vals$ID, FUN=pct, p=c(41,42,43)))

# Plot results
plot(lc)
  plot(st_geometry(plots), pch=20, col="black", add=TRUE)
  plot(st_geometry(plots[plots$pct.forest >= 0.25 ,]), pch=20,
         cex=2, col="red", add=TRUE)
```

# 2.4 Quantifying landscape structure

## Read data

Read "plots.shap" and "landcover.tif" Calculating landscape metrics for a entire landscape


```r
plots <- st_read(file.path(data.dir, "plots.shp")) #read in plot data
land.cover <- rast(file.path(data.dir, "landcover.tif")) 
  plot(land.cover)
    plot(plots, pch=20, add=TRUE)
```

## Reclassifying to forest/non-forest

Let's say that you are interested in forest/non-forest.  However, there are multiple forest classes (41,42, 43), you will need to reclassify as forest/non-forest (forest=41,42,43).  

|    See: classify, writing a function (ifelse) the calling app or using terra's native method for ifelse, ifel


```r
# Three different approaches are presented, please pick one and create
# a forest/non-forest raster "forest)

# three reclassify solution for forest/nonforest
m <- c(0,40.8, 0,40.9,43.1,1,43.9,91,0)
reclass <- matrix(m, ncol=3, byrow=TRUE)
forest <- classify(land.cover, reclass)

# function solution, much more stable. 
#   ifelse as a function 
fnf <- function(x) { ifelse( x == 41, 1, 
                       ifelse( x == 42, 1, 
                         ifelse( x == 43, 1, 0)))
    }						 
  forest <- app(land.cover, fun=fnf)

# ifelse directly as ifel method
forest <- ifel(land.cover == 41, 1, 
            ifel(land.cover == 42, 1, 
              ifel(land.cover == 43, 1, 0)))

plot(forest)
  plot(plots, pch=20, add=TRUE)
```

## Smooth by calculating percent forest

While forest at a cell may be important, you want to smooth your result and put the overall amount of forest in context. Calculate percent forest within 11x11 window. Create a function for a calculating percent and create a new raster that is pct.forest in a 11 X11 window 

See: length of target value, focal  


```r
pct <- function(x) { round( (length(x[x == 1]) / length(x)), 4) } 
pct.forest <- focal(forest, w=matrix(1,nrow=11,ncol=11), fun=pct)
```

## Forest cores

Next you wish to identify forest cores. Calculate 60 percent volume of forest percent to identify core areas, based on the above focal fractional forest results. Unfortunately, the function to return percent volume requires a raster class input so, you will have to coerce rast to raster (you can do it on the fly). 

|    See; raster.vol


```r
cores <- raster.vol(pct.forest, p=0.60)
  cores[is.na(cores)] <- 0 #replace non-core areas (NA) with 0
    cores <- mask(cores, forest)
  
par(mfrow=c(1,2))
  plot(pct.forest)  
    plot(cores)
```

## Landscape-level metrics

Describe the landscape using landscape metrics and compare forest to forest cores. See: landscapemetrics, pland, contagion, proportion of like adjacency (many other available metrics, select those you think are most meaningful)

See; lsm_c_pland, lsm_l_pladj, lsm_l_contag  


```r
# Percent landscape
( forest.pland <- lsm_c_pland(forest, directions=8) )
( cores.pland <- lsm_c_pland(cores, directions=8) )

# contagion
( forest.contag <- lsm_l_contag(forest, verbose=TRUE)$value )
( core.contag <- lsm_l_contag(cores, verbose=TRUE)$value )

# proportion of like adjacencies 
( forest.plaj <- lsm_l_pladj(forest)$value )
( core.plaj <- lsm_l_pladj(cores)$value )
```

## Sample-level metrics

Calculating landscape metrics for sample locations is a powerful way to compute covariates. Calculate landscape metrics for plots for both forest and cores. 

|    See; sample_lsm,


```r
# Print available metrics 
am <- as.data.frame(list_lsm())

# Subset to landscape level metrics
LM <- am[am$level == "landscape",] 

# Metric by type (full names)
tapply(LM$name, LM$type, unique)
 
# Metric by type (returned names)
tapply(LM$metric, LM$type, unique)

## class and patch level metrics  
# CM <- am[am$level == "class",] 
# PM <- am[am$level == "patch",]   

# Calculate sample metrics with a 500m buffer
mfnf <- as.data.frame(sample_lsm(forest, y = plots, plot_id = plots$ID, 
           size = 500, shape="circle", level = "landscape", 
		       type = "aggregation metric", 
           classes_max = 2,
           verbose = FALSE))
  head(mfnf)
  
# pull contagion 
contag <- mfnf[which(mfnf$metric %in% "contag"),]$value  
  plots$fnf_contag <- ifelse(is.na(contag), 0, contag)

# Evaluate core areas  
mcores <- as.data.frame(sample_lsm(cores, y = plots, plot_id = plots$ID, 
           size = 500, shape="circle", level = "landscape", 
		   type = "aggregation metric", 
           classes_max = 2,
           verbose = FALSE))
		   
contag <- mcores[which(mcores$metric %in% "contag"),]$value  
  plots$core_contag <- ifelse(is.na(contag), 0, contag)

# Plot core 
plot(cores, legend=FALSE)
  plot(plots["core_contag"], pch=20, cex=2, add=TRUE)
```
