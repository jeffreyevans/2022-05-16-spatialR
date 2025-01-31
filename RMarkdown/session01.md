---
source: Rmd
title: "spatialR workshop session 1 - Foundations of R for spatial analysis"
author:
  - Jeffrey S. Evans^[The Nature Conservancy, jeffrey_evans@tnc.org] 
date: "5/16/2022"
output:
  html_document: 
    toc: yes
    keep_md: yes
    code_folding: hide
---

**Objectives**

Introduction to coding structure, object classes, data manipulation, writing functions, for loops and reading/writing spatial data. We will introduce the basic foundations of R logic and coding syntax, object-oriented structure, object classes and looping. Building on these basics, we will then cover data manipulation of the various spatial class objects introducing indexing, query, merging and subsetting data. We will also introduce creating, reading and writing vector spatial classes.  

# **Setup**

## Add required libraries and set working environment


```{.r .fold-show}
invisible(lapply(c("sp", "raster", "spdep", "rgdal", "rgeos",  
                 "spatialEco", "sf", "terra", "spatstat", 
                 "spatstat.geom"), require, character.only=TRUE))

# set your working directory variable here
setwd("C:/spatialR/session01") 
  data.dir = file.path(getwd(), "data")
```

# **1.1 - Reading and writing of spatial classes**
 
## Read shapefile vector from disk

Read the "birds" shapefile, (see st_read) and display the first few rows of associated data. Hint; sf::st_read  


```r
( birds <- sf::st_read(file.path(data.dir, "birds.shp")) )
  str(birds)

## for reference, read sp object using rgdal
# birds <- rgdal::readOGR(file.path(getwd(), "data"), "birds")  
```

## Subset vector data

Subset the birds data, using a bracket index, using the condition Max2005 >= 20. Hint; x[x$col >= p,] ) or subset 
 

```r
( birds.sub <- birds[birds$Max2005 >= 20,] ) 
```

## Write vector data

Write the subset observations out to the data directory (data.dir) as new shapefile then, read back in. Hint; file.path, sf::st_write, sf::st_read 
 

```r
sf::st_write(birds.sub, file.path(data.dir, "birds_sub.shp"))
sf::st_read(file.path(data.dir, "birds_sub.shp"))

## for reference, for sp object using rgdal 
# writeOGR(birds.sub, file.path(getwd(), "data"), "birds_sub", 
#          driver="ESRI Shapefile", check_exists=TRUE, 
#	 	   overwrite_layer=TRUE)
```

## Read raster data

Read the isograv.img raster, located in the data directory, into a terra raster class object. Hint; file.path, rast


```r
( r <- rast(file.path(data.dir,"isograv.img")) )
```

## Read multi-band raster  

Make a multi-band raster object using bouguer, isograv, magnetic img rasters. Hint; rast, +1 for using list.files  


```r
r <- rast(c(file.path(data.dir,"bouguer.img"), 
          file.path(data.dir,"isograv.img"), 
          file.path(data.dir,"magnetic.img")))

( f <- list.files(data.dir, "img$", full.names = TRUE) )
( r <- rast(f[c(1,3,4)]) )
```

## Coercion of raster data

First, coerce r into a matrix/array. Ten coerce into a SpatialPixelsDataFrame. Unfortunately, terra does not provide this coercion but, the raster package does so, you have to coerce to a raster class object first. Hint; as.matrix, as, "SpatialPixelsDataFrame"  


```r
( r <- rast(list.files(data.dir, "img$", full.names = TRUE)[c(1,3,4)]) )
r.sp <- as(stack(r), "SpatialPixelsDataFrame")
  class(r.sp)
  head(r.sp@data)
  plot(r.sp)
```

## Write raster data

I prefer the geo tiff format with LZW compression. You do not have to specify datatype but, it is good to know how to control bit depth. Here we specify INT1U which is float -3.4e+38 to 3.4e+38. Note that if you are writing an sp raster type you must use writeGDAL. Hint; writeRaster with gdal and datatype arguments.  


```r
( r <- rast(list.files(data.dir, "img$", full.names = TRUE)[c(1,3,4)]) )
writeRaster(r, file.path(data.dir, "test.tif"), 
            overwrite=TRUE, gdal=c("COMPRESS=LZW"),
		        datatype='INT1U')
```

# **1.2 - Indexing and query of spatial vector classes**

## Create point vector

We will use the meuse dataset for all of these exercises, add the data and coerce to sf points. Hint; st_as_sf



```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

## sp coersion of data.frame to spatial points object
#  coordinates(meuse) <- ~x+y
```

## Subset rows of point vector

Subset the first 10 rows of meuse to a new dataset. Hint: Use a standard bracket index, remember the comma position for rows verses columns. Observations in an sp object are by row 


```r
( msub <- meuse[1:10,] )
```

##  Create random sample

Create a random sample of meuse (n=10). Hint; sample with 1:nrow(meuse) to create sample index


```r
( mrs <- meuse[sample(1:nrow(meuse), 10),] )
  plot(st_geometry(mrs))
```

## Subset using bracket query   

Query the meuse attribute "copper" to subset data to greater than/equal to 75th percentile of copper, plot results. Hint; bracket index using ">=" and quantile function 


```r
( cop075 <- meuse[meuse$copper >= quantile(meuse$copper, p=0.75),] )
  plot(cop075["copper"])
```

## Query to get percent  

Calculate the percent of class 1 in "soil" attribute using a brack query 


```r
nrow(meuse[meuse$soil == "1",]) / nrow(meuse)
```

## Aggregrated statistics 

Calculate the mean of cadmium for all soil classes. Hint; tapply


```r
tapply(meuse$cadmium, meuse$soil, mean)
```

## Random sample polygons 

Buffer observsations 1, 50 and 100 to 500m and then create 10 random samples for each polygon. Hint; st_buffer, st_sample, for or lapply, st_as_sf 
  		 

```r
p <- st_buffer(meuse[c(1,50,100),], dist=500)
  s <- st_sample(p, size = 10) 
    plot(st_geometry(p))
      plot(s, pch=20, add=TRUE)
   
# Wait, that's not 10 per-polygon. We need to iterate over
# the polygons (for or lapply)

s <- do.call(rbind,   
  lapply(1:nrow(p), function(i) { st_as_sf(st_sample(p[i,], 
         size = 10))} ) )     

plot(st_geometry(p))
  plot(s, pch=20, add=TRUE) 
```

## Distance-based random sample 

Draw a distance based random sample from a single observation drawn from meuse (sp) using; xy <- meuse[2,] Use 15-100 and 100-200 for distances with 50 random samples, plot results. Hint; sample.annulus  



```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

xy <- meuse[2,]

rs100 <- sample.annulus(xy, r1=50, r2=100, n = 50, type = "random")
rs200 <- sample.annulus(xy, r1=100, r2=200, n = 50, type = "random")

plot(st_geometry(rs200), pch=20, col="red")
  plot(st_geometry(rs100), pch=20, col="blue", add=TRUE)
  plot(st_geometry(xy), pch=20, cex=2, col="black", add=TRUE)
  legend("topright", legend=c("50-100m", "100-200m", "source"), 
         pch=c(20,20,20), col=c("blue","red","black"))
```

# **1.3 Functions**

## Step through and dissect function    

Calculate the Nearest Neighbor Index (NNI), using spatialEco::nni function, using meuse (sp).

Then, step through and dissect the the function by typeing spatailEco::nni to return the code then (nni is included in collopased code block):

a. defining parameters x = meuse and win = "hull" 

b. stepping through each line and if block, exploring the value and class of each output 


```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

nni(meuse)

nni <- function (x, win = c("hull", "extent")) {
    if (!inherits(x, "sf")) 
        stop(deparse(substitute(x)), " must be an sf POINT object")
    if (unique(as.character(sf::st_geometry_type(x))) != "POINT") 
        stop(deparse(substitute(x)), " must be an sf POINT object")
    if (win[1] == "hull") {
        w <- spatstat.geom::convexhull.xy(sf::st_coordinates(x)[, 
            1:2])
    }
    if (win[1] == "extent") {
        e <- as.vector(sf::st_bbox(x))
        w <- spatstat.geom::as.owin(c(e[1], e[3], e[2], e[4]))
    }
    x <- spatstat.geom::as.ppp(sf::st_coordinates(x)[, 1:2], 
        w)
    A <- spatstat.geom::area.owin(w)
    obsMeanDist <- sum(spatstat.geom::nndist(x))/x$n
    expMeanDist <- 0.5 * sqrt(A/x$n)
    se <- 0.26136/((x$n^2/A)^0.5)
    nni <- obsMeanDist/expMeanDist
    z <- (obsMeanDist - expMeanDist)/se
    return(list(NNI = nni, z.score = z, p = 2 * stats::pnorm(-abs(z)), 
        expected.mean.distance = expMeanDist, observed.mean.distance = obsMeanDist))
}


x = meuse
win = "hull"

w <- spatstat.geom::convexhull.xy(sf::st_coordinates(x)[,1:2])
x <- spatstat.geom::as.ppp(sf::st_coordinates(x)[,1:2], w)
A <- spatstat.geom::area.owin(w)
obsMeanDist <- sum(spatstat.geom::nndist(x))/x$n
expMeanDist <- 0.5 * sqrt(A / x$n)
se <- 0.26136 / ((x$n**2.0 / A)**0.5)
nni <- obsMeanDist / expMeanDist
z <- (obsMeanDist - expMeanDist) / se
p = 2*stats::pnorm(-abs(z))
```

## Write observed mean distance function 

Write a function that returns observed mean distance from the above nni function, don't worry about bells-and-whistles but write it to take an sf object. The object to return from the nni function is "obsMeanDist"


```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")
  
omd <- function(x) {
    w <- convexhull.xy(st_coordinates(x))
    x <- as.ppp(st_coordinates(x), w)
    A <- area.owin(w)
    obsMeanDist <- sum(nndist(x)) / x$n
  return(obsMeanDist)
}

omd(meuse)
```

# **1.4 Basic plotting of spatial objects**

## Plot attribute query  

Plot only soil class 1, Then, Make a 4 panel plot window and plot all points, and soil classes 1, 2 and 3 as separate plots. You need to use brackets ["soil"] to define which attribute you wish to plot or use st_geometry. To set the plot window to muliple pannels use par(mfrow=c(2,2))   

hint; plot can accept a bracket index to subset the data. 


```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

plot(meuse[meuse$soil == "1",]["soil"], pch=19)

par(mfrow=c(2,2))
  plot(st_geometry(meuse), pch=19)
    box()
  plot(st_geometry(meuse[meuse$soil == "1",]), pch=19)
    box()
  plot(st_geometry(meuse[meuse$soil == "2",]), pch=19)
    box()
  plot(st_geometry(meuse[meuse$soil == "3",]), pch=19)
    box()
```

## Plot nominal colors 

Create a color vector for the soil column and plot meuse by soil class colors (see ifelse, plot with col and pch arguments, use "red", "green" and "blue" for your "col" colors). Hint; you can pass a vector of colors to the col argument in plot. 


```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

my.col <- ifelse(meuse$soil == "1", "red",
            ifelse(meuse$soil == "2", "green", 
			        ifelse(meuse$soil == "3", "blue", NA)))
			   
plot(st_geometry(meuse), pch=19, col=my.col)
```

## Plot continuous colors 

Using a continuous attribute (eg., cadmium) in meuse, define breaks and plot using the breaks argument.   


```r
data(meuse)
meuse <- st_as_sf(meuse, coords = c("x", "y"), crs = 28992, 
                  agr = "constant")

bks <- seq(min(meuse$cadmium), max(meuse$cadmium), 
                by = diff(range(meuse$cadmium))/10) 
  plot(meuse["cadmium"], breaks = bks, pch=20)
```
