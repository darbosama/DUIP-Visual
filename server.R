#
# This is the server logic of a Shiny web application. You can run the 
# application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
# 
#    http://shiny.rstudio.com/
#

library(shiny)
library(ggplot2)
library(dplyr)
library(reshape2)

#Read in data
short <- read.csv("~/alldata.csv")

#Keep only first 14 indicators
short <- subset(short, Indicator.Number <= 14)

#select variables for analysis
myvars <- c("Awardee","Program","Category","Indicator.Number","Indicator.Name",
            "X2013.Age.Adjusted.Rate","X2014.Age.Adjusted.Rate","X2015.Age.Adjusted.Rate")
short <- short[myvars]

#set all zeros to NA
short[short == 0] <- NA

#change column names to year numbers
colnames(short)[6:8] <- 2013:2015

#create long data frame with with years as new variable
data = melt(short, measure.vars = c("2013","2014","2015"))

#change state names to lower-case for merge
data["Awardee"] <- mutate_all(data["Awardee"], funs(tolower))

#change indicator values and years to numeric data
data$value <- as.double(data$value)
data$variable <- as.double(data$variable)

#set year 2013 to zero to aid in interpretability of regression intercepts
data$variable <- data$variable - 1

#remove rows with missing data to reduce data frame size
slopes <- data[complete.cases(data[ , "value"]),]

#add variable representing number of data points per state per indicator
#and add variable for mean of all years
#this is used to exclude states / indicators with too few observations for regression
slopes %>%
  group_by(Awardee, Indicator.Number) %>%
  mutate(valuemean = mean(value)) %>%
  mutate(number = n()) -> slopes

#add new variable Slope - regression coefficient of value on year for each state and indicator
slopes[slopes$number > 2,] %>%
  group_by(Awardee, Indicator.Number) %>% # You can add here additional grouping variables if your real data set enables it
  do(mod = lm(value ~ variable, data = .)) %>%
  mutate(Slope = summary(mod)$coeff[2]) %>%
  mutate(Intercept = summary(mod)$coeff[1]) %>%
  select(-mod) %>%
  inner_join(slopes, by = c("Awardee", "Indicator.Number")) -> slopes

#adjust years to range from 2012 to 2016
data$variable <- data$variable + 2013

#import shape data for states
states <- map_data("state")

#change state name column in state shape data frame to match indicator data
colnames(states)[5] <- "Awardee"

#create new data frame with geographical center points for states (long and lat) 
centroids <- maps:::apply.polygon(map("state", plot=FALSE, fill = TRUE), maps:::centroid.polygon)
centroids <- centroids[!is.na(names(centroids))]
centroid_array <- Reduce(rbind, centroids)
dimnames(centroid_array) <- list(gsub("[^,]*,", "", names(centroids)),
                                 c("long", "lat"))
label_df <- as.data.frame(centroid_array)
label_df$Awardee <- rownames(label_df)

#create new variable sign that indicates whether beta coefficient is positive or negative
slopes[["sign"]] = ifelse(slopes[["Slope"]] >= 0, "positive", "negative")

#merge center point data frame with state shape and indicator data
slopes <- inner_join(label_df, filter(slopes), by = "Awardee")

server <- function(input, output) {
  output$coolplot <- renderPlot({
    filtered <-
      data %>%
      filter(
        Indicator.Number == input$indicatorInput,
        variable == input$yearInput
      )
    
    newslope <- filter(slopes, Indicator.Number == input$indicatorInput)
    
    #merge state shape data with indicator data
    filtered <- inner_join(filtered, states, by = "Awardee")
    
    ggplot(data = filtered) + 
      geom_polygon(data = map_data("state"), aes(x=long, y = lat, fill = value, group = group), fill = "grey", color = "white") +
      geom_polygon(aes(x = long, y = lat, fill = value, group = group), color = "grey40") + 
      scale_fill_gradient2(low = 'white', mid = 'lightblue', high = 'darkblue', name = paste(input$yearInput[1],"Value"), 
                           limits=c(0, max(subset(slopes, Indicator.Number == input$indicatorInput)$value))) +
      geom_point(data = newslope, aes(long, lat, size = (abs(Slope)), color = sign, shape = sign), fill = "white") +
      scale_size(name = "Yearly Change") +
      scale_shape_manual(values=c(24, 25), name = "Trend", labels = c("Getting Better","Getting Worse")) +
      scale_color_manual(values=c("darkgreen", "red"), name = "Trend", labels = c("Getting Better","Getting Worse")) +
      coord_fixed(1.3) +
      theme(axis.line=element_blank(),
            axis.text.x=element_blank(),
            axis.text.y=element_blank(),
            axis.ticks=element_blank(),
            axis.title.x=element_blank(),
            axis.title.y=element_blank(),
            panel.background=element_blank(),
            panel.border=element_blank(),
            panel.grid.major=element_blank(),
            panel.grid.minor=element_blank(),
            plot.background=element_blank())
    
  })
  
  output$trendplot <- renderPlot({
    filtered <-
      data %>%
      filter(
        Indicator.Number == input$indicatorInput
      )
    
    ggplot(filtered,aes(variable,value)) +
      stat_summary(fun.data = "mean_se", color = "blue", size = 1) + 
      geom_smooth(method='lm',fullrange=TRUE) + 
      xlim(2013, 2018) +
      labs(x = "Year", y = paste("Indicator # ",input$indicatorInput))
    
  })
  
  output$results <- renderTable({
    filtered <-
      short %>%
      filter(
        Indicator.Number == input$indicatorInput
      ) %>%
      select(Awardee, "2013", "2014", "2015")
    filtered
  })
  
}