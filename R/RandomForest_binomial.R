---
source: Rmd
title: "spatialR workshop - Random Forests for Binominal probabilistic models"
author:
  - Jeffrey S. Evans^[The Nature Conservancy, jeffrey_evans@tnc.org] 
date: "5/18/2022"
output:
  html_document: 
    toc: yes
    keep_md: yes
    code_folding: hide
---

**Objectives**

I will introduce the conceptual and mathematical foundations of recursive partitioning, ensemble and Random Forests methods along with implementation of a binomial (probabilistic) predictive model. In a probabilistic binomial instance, Random Forest does need a null [0,1]. In this example we will be using surveyed data representing presence/absence. However, when this is not the case methods must be employed to create a pseudo absence to act as the null. The simplest sample framework is a random or systematic sample. However, there are numerous issues with a null that is disconected from the spatial process observed in the data. The pseudo.absence function in the spatialEco library uses an isotropic intensity estimate to create sample weights in generating a random sample. This incorporates a continuous gradient of the spatial process in the observed data. 

In this exercise, we will leverage a spatial sample and raster data representing various hypothesized ecological processes associated with our species. We will employ a model selection procedure, evaluate the significance of the selected parameters, fit a final model, estimate the spatial uncertainty and perform model validation to evaluate fit and performance. Finaly, we will explore inferential methods using partial dependence plots to evaluate functional relationships and take a brief look at Shapley analysis for individual and aggregated relationships.    

# **Setup**

## Add required libraries and set working environment


```{.r .fold-show}
invisible(lapply(c("sf", "spatialEco", "terra", "randomForest", 
                   "rfUtilities", "ggplot2", "ranger", "fastshap", 
                   "pdp", "ggbeeswarm"), 
		  require, character.only=TRUE))

# set your working and data directories here
setwd("C:/spatialR/RandomForests")
  data.dir = file.path(getwd(), "data")
    if(!dir.exists(file.path(getwd(), "results")))
      dir.create(file.path(getwd(), "results")) 
    results.dir = file.path(getwd(), "results")
```

# **Data preparation**
 
## Read shapefile vector and img rasters from disk

Read species observations "spp.shp" to "spp" sf object and create a stack "xvars" of rast calss rasters excluding "elev.img". Hint; st_read, list.files, rast


```r
spp <- st_read(file.path(data.dir, "spp.shp"))

# Create raster stack (with elev removed)
( rlist = list.files(data.dir, pattern="img$", full.names=TRUE) )
  ( xvars <- rast(rlist[-6]) )
    names(xvars) <- rm.ext(basename(sources(xvars)))  
```


## Extract raster values

Extract raster values from "xvars" using "spp" sf object, add results to spp. Hint; extract, cbind


```r
e <- extract(xvars, vect(spp))
  spp <- cbind(spp, e[,-1])
    plot(spp["ffp"], pch=20)
```

## Check data balance

Coerce "Present" attribute, in spp, to factor and check balance of data
by evaluating the percent of each class Hint; factor, table



```r
spp$Present <- factor(spp$Present)
  levels(spp$Present)

# here is one way, is there a simpler approach?
( nrow(spp[spp$Present == 1, ])[1] / nrow(spp)[1] ) * 100  

# Perhaps
prop.table(table(spp$Present))  
```

## Check for collinearity and multi-collinearity

Test the design matrix for multi-collinearity and remove any collinear variables. Remove by permuted frequency > 10. Hint; multi.collinear, collinear

Is there a difference when permutation (perm = TRUE) is applied? 

Do you find collinear after addressing multi-collinearity?


```r
( ml <- multi.collinear(st_drop_geometry(spp[,3:ncol(spp)]), p=0.05) )

( ml <- multi.collinear(st_drop_geometry(spp[,3:ncol(spp)]), 
perm=TRUE, p=0.05) )
  rm.vars <- ml[ml$frequency > 0,]$variables
   if(length(rm.vars) > 0) 
     spp <- spp[,-which(names(spp) %in% rm.vars)]

cl <- spatialEco::collinear(st_drop_geometry(spp[,3:ncol(spp)]))
  if(length(cl) > 0) 
    spp <- spp[,-which(names(spp) %in% cl)]
```

## Create data withhold

Create a 10% data withhold, balanced across classes, and then remove from training data. We are not going to use this but, it is good to know how to split data. Hint; sample, which


```r
n = round(nrow(spp) * 0.10, 0)
idx <- c(sample(which(spp$Present == "0"), n/2),
         sample(which(spp$Present == "1"), n/2))

# split withhold and train
spp.withold <- spp[idx,]
spp.train <- spp[-idx,]

plot(st_geometry(spp.train), pch=20)
  plot(st_geometry(spp.withold), pch=20, col="red", add=TRUE)
```

# **Specify probabilistic binomial model**

## Apply a model selection procedure 

Create an initial random forests model object, with 501 Bootstrap replicates, to evaluate model efficacy. Then, apply a model selection procedure. Use "mir" for the imp.scale argument. The response (y) is "Present" and independent variables are all columns >= 2. Use st_drop_geometry(spp) to create a data.frame "dat".  Hint; randomForest, rf.modelSel 


```r
b = 501
set.seed(42)
dat <- st_drop_geometry(spp) 


randomForest(x=dat[,-c(1,2)], y=dat[,"Present"], ntree = b)

( rf.model <- rf.modelSel(x=dat[,-c(1,2)], 
                          y=dat[,"Present"], 
                          imp.scale="mir", ntree=b) )
```

## Evaluate selected parameter significance 	

Now, we will the significance of the selected paramters using the Altmann et al. (2010) permutation test where; the distribution of the importance under the null hypothesis is of no association to the response.  

First, Subset parameters in dat to those returned in the model selection. Second, fit a ranger random forest model, using the selected paramters then third, permute the model. Hint; ranger, importance_pvalues  


```r
# Create vector of selected parameter names
#( sel.vars <- rf.model$selvars )
( sel.vars <- rf.model$parameters[[3]] )

# subset to selected parameters
dat <- dat[,c("Present", sel.vars)]

# Fit model to test parameter significance 
( rf.exp <- ranger(Present ~ ., data = dat, probability = FALSE, 
                  num.trees = b, importance="impurity_corrected") )	

# Test variable significance p-value
( imp.p <- as.data.frame(importance_pvalues(rf.exp, method = "altmann", 
                         formula = Present ~ ., data = dat) ))
  pvars <- rownames(imp.p)[which(imp.p$pvalue < 0.05)] 

# Subset to significant parameters
dat <- data.frame(Present=factor(dat$Present), dat[,pvars])
```


## Fit final model	

Specify final fit model using selected variables from the model selection and paramter significance. Use probability = TRUE argument so that we are specifying a probabilistic random forests (Malley et al. 2012). Keep the inbag and importance in the model using keep.inbag and importance arguments. Hint; ranger


```r
( rf.prob <- ranger(Present ~ ., data = dat, probability = TRUE, 
                    keep.inbag=TRUE, num.trees = b, 
				            importance="permutation") )

# also fit randomForest class object for later use
rf.fit <- randomForest(x=dat[,-1], y=dat[,1], ntree=b)
```

## Derive importance	

Pull the importance values from the resulting fit model and create a dotplot of the feature contribution. Hint; names(rf), order, dotchart 


```r
imp <- rf.prob$variable.importance
  imp <- imp[order(imp)]	
    dotchart(imp, names(imp), pch=19, main="Variable Importance")
```

# **Model validation**

## Confusion matrix based statistics 

Create an obs.pred data.frame contaning observed response variable and estiamated probabilities. For an evaluation of accuracy, we can derive numerious statistics that leverage the confusion matrix. To do this we need to transform the probabilities to a [0,1] outcome so that it is compariable with our response variable. Fist, manually calculate percent correctly classified (using a 0.65 threshold for the probabilies). Then, you can calll a function that returns several appropriate statistics.     

Hint; ifelse, accuracy


```r
obs.pred <- data.frame(observed=as.numeric(as.character(dat[,1])),
                       prob=predict(rf.prob, dat[,-1])$prediction[,2])

# calculate percent correctly classified
p = 0.65
op <- (obs.pred$observed == ifelse(obs.pred$prob >= p, 1, 0))
  pcc <- (length(op[op == "TRUE"]) / length(op))*100
cat("Percent correctly classified:", pcc, "\n")

# Call accuracy function
accuracy(table(obs.pred$observed, ifelse(obs.pred$prob >= p, 1, 0)))

# Plot estimated probability distributions for class-level predictions
d1 <- density(obs.pred[obs.pred$observed == 1,]$prob)
d0 <- density(obs.pred[obs.pred$observed == 0,]$prob)
plot(d1, type="n", xlim=c(0,1), ylim=c(min(d1$y,d0$y),max(d1$y,d0$y)),   
     main = "Estimated probability of present class")
	polygon(d1, col=rgb(0, 0, 1, 0.5))
    polygon(d0, col=rgb(1, 0, 0, 0.5))	
```

## Log Loss

Log loss is defined as the negative log-likelihood of the prevleance, given the predicted probabilities. The advantage of log loss is that the further a class is away from its predicted probability, the more it is penalized thus, yeilding an honest measure of performance. The log loss bounds between 0 and infinity (the lower the more accurate).


```r
ll <- logLoss(y = obs.pred[,"observed"], p = obs.pred[,"prob"])
  cat("Global log loss:", ll, "\n")
```

## cross-validation 

Unlike a traditional n-fold cross-validation, we will perform a Bootstrap approach where the full model is evaluated against numerious Bootstraped models representing different realizations of data (Evans et al., 2011). This allows us to evaluate the error distribution and variance. Limit the n argument to 99 for computation brevity. Hint; rf.crossValidation (needs a randomForest objet) 

Evans J.S., M.A. Murphy, Z.A. Holden, S.A. Cushman (2011). Modeling species
  distribution and change using Random Forests CH.8 in Predictive Modeling 
  in Landscape Ecology eds Drew, CA, Huettmann F, Wiersma Y. Springer


```r
if(exists("rf.fit")){
  ( cv <- rf.crossValidation(x=rf.fit, xdata=dat[,-1], 
                  ydata = dat[,1], p = 0.1, n = 99) )
}
```

## Sensitivity test 

We can find a supported probability threshold by appling a sensitivity test (Jimenez-Valverde & Lobo 2007), in our case, using the kappa as the objective statistic. Hint; occurrence.threshold

Jimenez-Valverde, A., & J.M. Lobo (2007). Threshold criteria for conversion of
  probability of species presence to either-or presence-absence. 
  Acta Oecologica 31(3):361-369 


```r
plot(occurrence.threshold(rf.fit, dat[,-1], class="1", 
                     p = seq(0.1, 0.7, 0.02),
                     type = "kappa"))	
```

## Prediction calibration 

We can perform a calibration of posterior probability to minimize log loss using an isotonic regression approach (Niculescu-Mizil & Caruana 2005). This is particuraly relevant if you are having tail-prediction issues. Hint; probability.calibration 

Niculescu-Mizil, A., & R. Caruana (2005) Obtaining calibrated probabilities
  from boosting. Proc. 21th Conference on Uncertainty in Artificial 
  Intelligence (UAI 2005). AUAI Press. 


```r
p.cal <- probability.calibration(y = obs.pred[,1], p = obs.pred[,2], 
                        regularization = FALSE)

# Plot estimated and calibrated probability distributions 
d1 <- density(obs.pred$prob)
d0 <- density(p.cal)
plot(d1, type="n", xlim=c(0,1), ylim=c(min(d1$y,d0$y),max(d1$y,d0$y)),   
     main = "Estimated probability of present class")
	polygon(d1, col=rgb(1, 0, 0, 0.2))
    polygon(d0, col=rgb(0, 0, 1, 0.2))
```

# **Spatial predictions**

## Subset rasters 

Subset raster stack to selected variables, remember to use double bracket to subset raster rast or stack/brick objects						 


```r
sel.vars <- names(rf.prob$variable.importance)
xvars <- xvars[[which(names(xvars) %in% sel.vars)]] 
```

## Create prediction raster

Make a spatial prediction of rf model to raster object. To accommodate a ranger random forest model we need to first write a prediction wrapper function to pass to the terra::predict function. At the current version of terra the predict function is strugling with NA values in the raster paramters. We incoporate a rough fix into the wrapper function. Hint; predict.ranger, terra::predict, predict.randomForest 


```r
predict.prob <- function(model, data, i=2) {
  data <- as.data.frame(data)
  idx <- unique(as.numeric(which(is.na(data), arr.ind=TRUE)[,1]))
    data <- data[-idx,]
  p <- as.numeric(ranger:::predict.ranger(model, data = data,
                  type = "response")$predictions[,i])
	if(length(idx) > 0) 
	  p <- spatialEco::insert.values(p, NA, idx)
	return(p)			  
}
sdm <- predict(xvars, rf.prob, fun=predict.prob)
  writeRaster(sdm, file.path(results.dir, "rf_probs.tif"),
              overwrite=TRUE)

dev.new(height=8,width=11.5)
plot(sdm)
  plot(st_geometry(spp[spp$Present == "1" ,]), add = TRUE, 
       col="red", pch=20, cex=0.75)
  plot(st_geometry(spp[spp$Present == "0" ,]), add = TRUE, 
       col="blue", pch=20, cex=0.75)		
```

## Spatial uncertainty 

We can estimate a meaure of spatial uncertainty using Wager's et al., (2014) Infinitesimal Jackknife approach. 

Note; it is not recommended that you run this as it is memory/processes intensive and slow (which is why it is commented out)

Wager, S., T. Hastie, & B. Efron (2014) Confidence Intervals for Random 
  Forests: The Jackknife and the Infinitesimal Jackknife. J Mach Learn 
  Res 15:1625-1651.
  

```r
predict.se <- function(model, data, i=2) {
  data <- as.data.frame(data)
  idx <- unique(as.numeric(which(is.na(data), arr.ind=TRUE)[,1]))
    data <- data[-idx,]
  p <- as.numeric(ranger:::predict.ranger(model, data = data,
                  type = "se", se.method = "infjack")$se[,i])
	if(length(idx) > 0) 
	  p <- spatialEco::insert.values(p, NA, idx)
	return(p)			  
}

# sdm.se <- predict(xvars, rf.prob, fun=predict.se)
 
# # Add upper and lower confidence intervals
# sdm <- c(sdm, sdm - (sdm.se * 1.96),
#                sdm + (sdm.se * 1.96) )				   
#   names(sdm) <- c("sdm", "lower.ci", "upper.ci")
 
# writeRaster(sdm, file.path(data.dir, "sdm.tif"), 
#             overwrite=TRUE)
```


# **Functional relationships and inference**

## Partial dependence probability plots

The partial dependence plot shows the marginal effect one or two features have on the predicted outcome (J. H. Friedman 2001). The partial function tells us for given value(s) of a feature, what the average marginal effect on the prediction. This is done by holding the parameters, excluding the one of intrests, at their mean and estimating the model. 

Create partial dependence  probability plots to explore functional relationships. Hint; partial, rf.partial.prob, bivariate.partialDependence

Friedman, J.H. (2001) Greedy function approximation: A gradient boosting
  machine. Annals of statistics: 1189-1232


```r
# Partial dependency plots
pp.map <- pdp::partial(rf.prob, pred.var = "map", plot = TRUE, 
                   which.class=2, prob = TRUE, train = dat[,-1], 
				   levelplot = TRUE, chull = TRUE, quantiles = TRUE, 
				   smooth=TRUE, plot.engine = "ggplot2")
      print(pp.map + ggtitle("Partial dependency for map"))
	  
pp.strmdist <- pdp::partial(rf.prob, pred.var = "strmdist", plot = TRUE, 
                   which.class=2, prob = TRUE, train = dat[,-1], 
				   levelplot = TRUE, chull = TRUE, quantiles = TRUE, 
				   smooth=TRUE, plot.engine = "ggplot2")
      print(pp.strmdist + ggtitle("Partial dependency for strmdist"))    
 
# Individual Conditional Expectation (ICE) plots display one line per instance 
#   showing how the instance’s prediction changes when a feature changes.
ice.map <- pdp::partial(rf.prob, pred.var = "map", plot = TRUE, ice=TRUE, 
                   center=TRUE, which.class=2, prob = TRUE, train = dat[,-1], 
				   levelplot = TRUE, chull = TRUE, quantiles = TRUE, 
				   smooth=TRUE, plot.engine = "ggplot2")
      print(ice.map + ggtitle("Individual Conditional Expectation for map"))

# Bivariate Partial dependency plots
pp.bv <- pdp::partial(rf.prob, pred.var = c("map", "strmdist"), 
                      grid.resolution = 40, which.class=2, prob = TRUE, 
					  train = dat[,-1])
	plotPartial(pp.bv, levelplot = FALSE, zlab = "occupancy", drape = TRUE,
            colorkey = FALSE, screen = list(z = -20, x = -60))			   
```

## Shapley analysis - aggregated 

Inference (using Shapley method)

Calculate and aggregate Shapley values for feature importance, depency and beeswarm plot


```r
dat <- data.frame(p=obs.pred$prob, dat)

pfun <- function(object, newdata, i = 2) {
  predict(object, data = newdata)$predictions[,i]
}

shap <- fastshap::explain(rf.prob, X = dat[,-c(1,2)], pred_wrapper = pfun, 
                          adjust=TRUE, nsim = 50)

# Feature dependency
prob <- autoplot(shap, type = "dependence", feature = "map", X = dat, 
                 alpha = 0.5, color_by = "p", smooth = TRUE, 
				   smooth_color = "black") +  
                     geom_smooth() +
				       scale_colour_gradient(low = "cyan", high = "red", na.value = NA)
  print(prob + ggtitle("Shapley dependency for map"))
  
classes <- unique(as.character(dat$Present))
  shap.df <- data.frame(class = as.character(dat$Present), shap)
    shap_df <- dplyr::as_tibble(do.call(rbind, 
	  lapply(unique(shap.df$class), function(j) { 
        apply(shap.df[shap.df$class == j,][-c(1,2)], MARGIN = 2, 
		  FUN = function(x) mean(x)) }) 
	))
      class(shap_df) <- class(shap)	

#### Shape Importance
shap_imp <- data.frame(Variable = names(shap)[-1],
  Importance = apply(shap_df, MARGIN = 2, FUN = function(x) sum(abs(x))) )
    shap_imp$Importance <- shap_imp$Importance / max(shap_imp$Importance) 
( simp <- ggplot(shap_imp, aes(reorder(Variable, Importance), Importance)) +
                 geom_col() + coord_flip() + xlab("") +
                 ylab("mean importance(|standardized shapley values|)") )

#### Beeswarm plot
shap.df <- data.frame(class = classes, p=dat$p, shap)
  shap_df <- data.frame(p = unlist(lapply(unique(shap.df$class), 
    function(j) median(dat[which(classes == j),]$p))),
     do.call(rbind, lapply(unique(classes), function(j) { apply(shap[shap.df$class == j,][,-1], 
	   MARGIN = 2, FUN = function(x) mean(x)) }) ) )

shap_group <- cbind(shap.df[,2], stack(shap.df[3:ncol(shap.df)]))	   
  names(shap_group) <- c("p", "shapley", "parameter")  

( bee <- shap_group %>%
  ggplot(aes(parameter, shapley, color = p)) +
    geom_beeswarm(priority='density', dodge.width=0.25, 
  	              alpha=0.40, size=3, shape=19) + 
  	  coord_flip() +
  	    scale_colour_gradient(low = "cyan", high = "red", na.value = NA) )
```

## Shapley analysis - individual (observation)

Create individual SHAP plots (select 4 random obs from "1" class)


```r
idx=sample(which(dat$Present == "1"), 4)
cat("Individual SHAP values for obs:", rownames(dat[idx,]), "\n")
grid.arrange(
  autoplot(shap, type = "contribution", row_num = idx[1]),
  autoplot(shap, type = "contribution", row_num = idx[2]),
  autoplot(shap, type = "contribution", row_num = idx[3]),
  autoplot(shap, type = "contribution", row_num = idx[4]),
ncol=2, nrow = 2)
```
