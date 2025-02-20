library(shiny)
library(bslib)
library(shinyjs)
# UI definition
ui <- page_navbar(
  title = "Tournament App",
  # First Tab: Tournament Designer
  nav_panel("Tournament Designer", 
            fluidPage(
              useShinyjs(),  # Ensure this is called outside tabPanel
              theme = bs_theme(version = 5),
              
              # Optional dark mode toggle
              
              
              textInput("max_min", "Calculation time per round (minutes):"),
              numericInput("rounds", "Enter number of rounds:", value = "", min = 1, step = 1),
              
              fluidRow(
                checkboxInput("D_check", "C-Optimization? (D-Optimization is default)", value = FALSE),
                conditionalPanel(
                  condition = "input.D_check == true",
                  tags$div(
                    style = "display: inline-block; width: 40%; height: 40px;",
                    textInput("D_values", "Enter weights (comma-separated):", value = "")
                  )
                )
              ),
              column(1, 
                     div(style = "width: 50px; display: inline-block;")),
              fileInput("file1", "Upload Player Info (Include Headers)", accept = ".csv"),
              tableOutput("file_data"),
              actionButton("run", "Calculate"),
              downloadButton("downloadFile", "Download Matches as Text File", disabled = TRUE),
              div(style = "margin-top: 30px;", 
                  downloadButton("downloadCsv", "Download Design (Needed for Variable Solver)", disabled = TRUE)
              )
            )
  ),
  
  # Second Tab: Variable Solver
  nav_panel("Variable Solver", 
            fluidPage(
              fluidRow(
                fileInput("file2", "Upload Design", accept = ".csv"),
                fileInput("file3", "Upload Results (Include Header)", accept = ".csv")
              ),
              uiOutput("conditional_checkbox"),
              actionButton("solve", "Solve"),
              uiOutput("betaVectorText")
            )
  ),
  nav_panel("Help",
            fluidPage(
              p(HTML("<b>Tournament Designer:</b><br>"), style = "font-size: 22px;"),
              p(HTML("<b>Calculation Time:</b> Controls the amount of time per round the program will optimize the design for. The number entered represents minutes, and decimal values are accepted.<br>")),
              p(HTML("<b>Number of Rounds:</b> Controls the amount of rounds that the program will calculate. Only positive integers are accepted.")),
              p(HTML("<b>C-Optimization:</b> Determines whether to create a C-Optimal Design or a D-Optimal Design. D-Optimal is the default. D-Optimization aims to maximize the determinant of the Fisher Information Matrix, resulting in an equally good estimation for each variable. If C-Optimization is checked, a prompt will come up to enter the weights for each variable. The weight for a given variable is how much significance it has in the design calculation. Each variable (except the intercept) has 2 weights, 1 for the home team, and 1 for the away team. The weights should be entered in the order that the trait appears in the player data. Decimal values are accepted.")),
              p(HTML("<b>Upload Player Info:</b> Upload the csv file of the information of the players. Do not include any columns for player names or indexes. The maximum amount of traits per player accepted is 5, any other columns will be omitted. Any numeric value will be accepted. Any rows with NA or empty data will be omitted.")),
              p(HTML("<b>Calculate:</b> Begins calculation of the design.")),
              p(HTML("<b>Download Matches as Text File:</b> Downloads the design of the tournament in a readable format. Do not use for the variable solver")),
              p(HTML("<b>Download Design:</b> Downloads the design to use for the variable solver. Highly recommended for any use to ensure easy calculation of variable estimates.")),
              p(HTML("<b>Variable Solver:</b><br>"), style = "font-size: 22px;"),
              p(HTML("<b>Upload Design:</b> Upload the design file generated by the tournament designer. File should be .csv, not .txt. If a design was generated during the current session, an option to use the last design will appear, not requiring for the upload of a design file.")),
              p(HTML("<b>Upload Results:</b> Upload the results of the tournament in a csv file with a header. Should all be in 1 column in the order the matches file generated has the matches.")),
              p(HTML("<b>Solve:</b> Solves for each of the variables."))
            )
  ),
  nav_item(input_dark_mode())
)
# Server logic
server <- function(input, output, session) {
  finalDesign = reactiveVal(NULL)
  calculation_done <- reactiveVal(FALSE)
  output$conditional_checkbox <- renderUI({
    if (calculation_done()) {
      checkboxInput("useLast", "Use last generated design?", value = FALSE)
    }
  })
  uploaded_data <- reactive({
    req(input$file1)
    dataInput = read.csv(input$file1$datapath)
  })
  
  observe({
    mode = input$mode
    toggle_dark_mode(mode)
  })
  
  useLast = reactiveVal(FALSE)
  observeEvent(input$solve, {
    useLast(input$useLast)
    if ((is.null(input$file2)) && !isTRUE(useLast())) {
      showModal(modalDialog(
        title = "Error",
        "Please upload a design file before proceeding.",
        easyClose = TRUE
      ))
      return()
    }
    if (is.null(input$file3)) {
      showModal(modalDialog(
        title = "Error",
        "Please upload a results file before proceeding.",
        easyClose = TRUE
      ))
      return()
    }
    if (isTRUE(useLast())) {
      designSolve = finalDesign()
    } else {
      designSolve = read.csv(input$file2$datapath)
    }
    results = as.matrix(read.csv(input$file3$datapath))
    designRows = nrow(designSolve)
    resultsRows = nrow(results)
    if (designRows != resultsRows) {
      showModal(modalDialog(
        title = "Error",
        "Please make sure the design has the same number of rows as the results (check results has 1 entry per match).",
        easyClose = TRUE
      ))
      return()
    }
    numBetas = ncol(designSolve)
    if (ncol(results) > 1) {
      removeResult = ncol(results) - 1
      for (i in 1:removeResult) {
        results = results[, -ncol(results)]
      }
    }
    results = as.numeric(results)  
    results = matrix(results, ncol = 1)
    designSolve = as.matrix(designSolve)
    fim = t(designSolve) %*% designSolve
    inv = solve(fim)
    betaVector = (inv %*% t(designSolve)) %*% results
    predictedValues = designSolve %*% betaVector
    sumMSE = 0
    for (i in 1:length(predictedValues)) {
      sumMSE = sumMSE + (results[i] - predictedValues[i])^2
    }
    df = nrow(designSolve) - ncol(designSolve)
    MSE = sumMSE / df
    deviations = apply(designSolve, 2, sd)
    SE = (MSE / sqrt(deviations))
    t_stats = betaVector / SE
    p_values = 2 * (1 - pt(abs(t_stats), df))
    print(MSE)
    print(SE)
    print(t_stats)
    print(p_values)
    betaString = ""
    for (i in 1:length(betaVector)) {
      if (i == 1) {
        betaString = paste("Intercept: ", round(betaVector[i], 4),  "| SE: ", round(SE[i], 4), "| t Statistic: ", round(t_stats[i], 4), "| p Value: ", round(p_values[i], 4), "<br>", sep = "")
      } else if (i %% 2 == 0) {
        betaString = paste(betaString, "Home Team Trait ", floor(i/2), ": ", round(betaVector[i], 4), "| SE: ", round(SE[i], 6), "| t Statistic: ", round(t_stats[i], 4), "| p Value: ", round(p_values[i], 4), "<br>", sep = "")
      } else {
        betaString = paste(betaString, "Away Team Trait ", floor(i/2), ": ", round(betaVector[i], 4),  "| SE: ", round(SE[i], 6), "| t Statistic: ", round(t_stats[i], 4), "| p Value: ", round(p_values[i], 4), "<br>", sep = "")
      }
      if (i == length(betaVector)) {
        betaString = paste(betaString, "Please note home vs away is arbitrary just to distinguish teams")
      }
      
    }
    output$betaVectorText <- renderUI({
      HTML(betaString)
    })
  })
  
  
  observeEvent(input$run, {
    if (is.null(input$file1)) {
      showModal(modalDialog(
        title = "Error",
        "Please upload a file before proceeding.",
        easyClose = TRUE
      ))
      return()
    }
    
    
    max_min <- as.numeric(input$max_min)
    if (is.na(max_min) || max_min < 0.1) {
      showModal(modalDialog(
        title = "Invalid Input",
        "Please enter a valid number for calculation time.",
        easyClose = TRUE
      ))
      return()
    }
    
    # Validate 'rounds' input
    rounds <- as.numeric(input$rounds)
    if (is.na(rounds) || rounds < 1) {
      showModal(modalDialog(
        title = "Invalid Input",
        "Please enter a valid number of rounds.",
        easyClose = TRUE
      ))
      return()
    }
    
    
    # Handle the 'D' value (C-Optimization logic)
    if (input$D_check) {
      D_values <- input$D_values
      if (D_values != "") {
        # Parse comma-separated input into a numeric vector
        CWeight <- as.numeric(unlist(strsplit(D_values, ",")))
        
        # Check if any values are NA (invalid input)
        if (any(is.na(CWeight))) {
          showModal(modalDialog(
            title = "Invalid Input",
            "Please enter valid numeric values for C Weights.",
            easyClose = TRUE
          ))
          return()
        }
        if (any(CWeight < 0)) {
          showModal(modalDialog(
            title = "Invalid Input",
            "Please enter all non-negative values for C Weights.",
            easyClose = TRUE
          ))
          return()
        }
        if (all(CWeight <= 0)) {
          showModal(modalDialog(
            title = "Invalid Input",
            "Please enter at least 1 value above 0 for C Weights.",
            easyClose = TRUE
          ))
          return()
        }
        
        # Successfully parsed C Weights
      } else {
        showModal(modalDialog(
          title = "Invalid Input",
          "Please enter weights for C-Optimization.",
          easyClose = TRUE
        ))
        return()
      }
    }
    withProgress(message = 'Running Simulations...', value = 0, {
      disable("run")
      
      bestDesign = NULL
      bestDet = -Inf
      simulations = 0
      bestMatches = NULL
      bestMatchesC = NULL
      bestDesignC = NULL
      bestInv = Inf
      bestDet = -Inf
      bestPairs = NULL
      bestPairsC = NULL
      dataInput = read.csv(input$file1$datapath)
      cleanedData = data.frame()
      outputString = "Round 1:\n"
      
      #Limit number of testable traits to 5
      print(dataInput)
      varsTesting = ncol(dataInput)
      colRemove = varsTesting - 5
      if (colRemove > 0) {
        for (i in 1:colRemove) {
          dataInput = dataInput[, -ncol(dataInput)]
        }
        varsTesting = 5
      }
      
      cleanedData = dataInput
      #Checking Input Data
      rowsRemove = integer()
      for (j in 1:ncol(cleanedData)) {
        for (i in 1:nrow(cleanedData)) {
          entry = cleanedData[i, j]
          if (is.null(entry) || length(entry) == 0) {
            rowsRemove = c(rowsRemove, i)
            next  
          }
          numEntry = as.numeric(entry)
          if (is.na(numEntry)) {
            rowsRemove = c(rowsRemove, i)
          }
        }
      }
      print(rowsRemove)
      if (length(rowsRemove > 0)) {
        rowsRemove = unique(rowsRemove)
        cleanedData = cleanedData[-rowsRemove, ]
      }
      
      #Make number of players divisible by 4
      
      num_players = nrow(cleanedData)
      if (num_players %% 4 != 0) {
        playersRemove = num_players %% 4
        cleanedData = head(cleanedData, -playersRemove)
        num_players = nrow(cleanedData)
      }
      print(cleanedData)
      rows = (2 * varsTesting) + 1
      C = input$D_check
      D = FALSE
      if (!C) {
        D = TRUE
      }
      
      #Rounds Edge Cases
      if (rounds < 1) {
        rounds = 1
      }
      if ((is.na(rounds)) || !exists("rounds")) {
        rounds = 1
      }
      
      #Normalize # of weights for C Optimization (Rows of FIM)
      if (!D) {
        if (length(CWeight) > rows) {
          CWeight = CWeight[1:rows]
        }
        if (length(CWeight) < rows) {
          appendZero = rows - length(CWeight)
          for (i in 1:appendZero) {
            CWeight = c(CWeight, 0)
          }
        }
      }
      
      print(varsTesting)
      #Assign Data
      playerFit <- as.numeric(cleanedData[, 1])
      
      if (varsTesting > 1) {
        playerSkill <- as.numeric(cleanedData[, 2])
      }
      if (varsTesting > 2) {
        playerHeight <- as.numeric(cleanedData[, 3])
      }
      if (varsTesting > 3) {
        playerAge <- as.numeric(cleanedData[, 4])
      }
      if (varsTesting > 4) {
        playerEquipment <- as.numeric(cleanedData[, 5])
      }
      
      #First Iteration
      start_time <- Sys.time()
      while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < (max_min * 60)) {
        
        #Shuffling Pairs
        playerIndices = 1:length(playerFit)
        shuffledIndices = sample(playerIndices)
        pairs = matrix(shuffledIndices, ncol = 2, byrow = TRUE)
        
        #Combining Pair Traits
        combinedFitness = sapply(1:nrow(pairs), function(i) {
          sum(playerFit[pairs[i, ]])
        })
        
        if (varsTesting > 1) {
          combinedSkill = sapply(1:nrow(pairs), function(i) {
            sum(playerSkill[pairs[i, ]])
          })
        }
        if (varsTesting > 2) {
          combinedHeight = sapply(1:nrow(pairs), function(i) {
            sum(playerHeight[pairs[i, ]])
          })
        }
        if (varsTesting > 3) {
          combinedAge = sapply(1:nrow(pairs), function(i) {
            sum(playerAge[pairs[i, ]])
          })
        }
        if (varsTesting > 4) {
          combinedEquipment = sapply(1:nrow(pairs), function(i) {
            sum(playerEquipment[pairs[i, ]])
          })
        }
        
        #Creating List of Pairs (and traits)
        design <- matrix(ncol = (varsTesting * 2) + 1, nrow = 0)
        cols <- list(Pair = 1:nrow(pairs), 
                     Player1 = pairs[, 1], 
                     Player2 = pairs[, 2], 
                     CombinedFitness = combinedFitness)
        
        if (varsTesting > 1) {
          cols$CombinedSkill <- combinedSkill
        }
        if (varsTesting > 2) {
          cols$CombinedHeight <- combinedHeight
        }
        if (varsTesting > 3) {
          cols$CombinedAge <- combinedAge
        }
        if (varsTesting > 4) {
          cols$CombinedEquipment <- combinedEquipment
        }
        
        result <- do.call(data.frame, cols)
        
        #Shuffling Matches & Making Matches List
        shuffledIndices = sample(1:nrow(result))
        matches = matrix(shuffledIndices, ncol = 2, byrow = TRUE)
        
        #Creating Design
        for (i in 1:nrow(matches)) {
          player1_index <- matches[i, 1]
          player2_index <- matches[i, 2]
          fitness1 = result[player1_index, "CombinedFitness"]
          fitness2 = result[player2_index, "CombinedFitness"]
          tempVector = c(1, fitness1, fitness2)
          if (varsTesting > 1) {
            skill1 = result[player1_index, "CombinedSkill"]
            skill2 = result[player2_index, "CombinedSkill"]
            tempVector = c(tempVector, skill1, skill2)
          } 
          if (varsTesting > 2) {
            height1 = result[player1_index, "CombinedHeight"]
            height2 = result[player2_index, "CombinedHeight"]
            tempVector = c(tempVector, height1, height2)
          }
          if (varsTesting > 3) {
            age1 = result[player1_index, "CombinedAge"]
            age2 = result[player2_index, "CombinedAge"]
            tempVector = c(tempVector, age1, age2)
          }
          if (varsTesting > 4) {
            equipment1 = result[player1_index, "CombinedEquipment"]
            equipment2 = result[player2_index, "CombinedEquipment"]
            tempVector = c(tempVector, equipment1, equipment2)
          } 
          design = rbind(design, t(tempVector))
        }  
        
        #Calculations (D Optimization)
        if (D) {
          fim = t(design) %*% design
          det = det(fim)
          if (det > bestDet) {
            bestDet = det
            bestDesign = design
            bestMatches = matches
            bestPairs = pairs
          }
          simulations = simulations + 1
        }
        
        #Calculation (C Optimization)
        if (!D) {
          fim = t(design) %*% design
          inv = solve(fim)
          invWeighted = 0
          for (i in 1:length(CWeight)) {
            invWeighted = invWeighted + (CWeight[i] * inv[i, i]) 
          }
          if (invWeighted < bestInv) {
            bestInv = invWeighted
            bestDesignC = design
            bestMatchesC = matches
            bestPairsC = pairs
          }
          simulations = simulations + 1 
        }
      }
      incProgress(1/rounds)
      if (D) {
        for (i in 1:nrow(bestMatches)) {
          pair1_idx <- bestMatches[i, 1]
          pair2_idx <- bestMatches[i, 2]
          pair1_players <- bestPairs[pair1_idx, ]
          pair2_players <- bestPairs[pair2_idx, ]
          outputString <- paste(outputString, "Player", pair1_players[1], "and", pair1_players[2], "vs Player",    pair2_players[1], "and", pair2_players[2], "\n")
        }
      }
      if (!D) {
        for (i in 1:nrow(bestMatchesC)) {
          pair1_idx <- bestMatchesC[i, 1]
          pair2_idx <- bestMatchesC[i, 2]
          pair1_players <- bestPairsC[pair1_idx, ]
          pair2_players <- bestPairsC[pair2_idx, ]
          outputString <- paste(outputString, "Player", pair1_players[1], "and", pair1_players[2], "vs Player",    pair2_players[1], "and", pair2_players[2], "\n")
        }
      }
      
      
      #Further Iterations
      if (D) {
        baseDesignD = bestDesign
      }
      if (!D) {
        baseDesignC = bestDesignC
      }
      
      roundsLeft = rounds - 1
      if (roundsLeft > 0) {
        for (k in 1:(roundsLeft)) {
          start_time <- Sys.time()
          bestInv = Inf
          bestDet = -Inf
          while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < (max_min * 60)) {
            playerIndices = 1:length(playerFit)
            shuffledIndices = sample(playerIndices)
            pairs = matrix(shuffledIndices, ncol = 2, byrow = TRUE)
            
            #Get Combined Traits for New Pairs  
            combinedFitness = sapply(1:nrow(pairs), function(i) {
              sum(playerFit[pairs[i, ]])
            })
            
            if (varsTesting > 1) {
              combinedSkill = sapply(1:nrow(pairs), function(i) {
                sum(playerSkill[pairs[i, ]])
              })
            }
            if (varsTesting > 2) {
              combinedHeight = sapply(1:nrow(pairs), function(i) {
                sum(playerHeight[pairs[i, ]])
              })
            }
            if (varsTesting > 3) {
              combinedAge = sapply(1:nrow(pairs), function(i) {
                sum(playerAge[pairs[i, ]])
              })
            }
            if (varsTesting > 4) {
              combinedEquipment = sapply(1:nrow(pairs), function(i) {
                sum(playerEquipment[pairs[i, ]])
              })
            }
            
            
            design <- matrix(ncol = (varsTesting * 2) + 1, nrow = 0)
            cols <- list(Pair = 1:nrow(pairs), 
                         Player1 = pairs[, 1], 
                         Player2 = pairs[, 2], 
                         CombinedFitness = combinedFitness)
            
            if (varsTesting > 1) {
              cols$CombinedSkill <- combinedSkill
            }
            if (varsTesting > 2) {
              cols$CombinedHeight <- combinedHeight
            }
            if (varsTesting > 3) {
              cols$CombinedAge <- combinedAge
            }
            if (varsTesting > 4) {
              cols$CombinedEquipment <- combinedEquipment
            }
            
            result <- do.call(data.frame, cols)
            
            shuffledIndices = sample(1:nrow(result))
            matches = matrix(shuffledIndices, ncol = 2, byrow = TRUE)
            design <- matrix(ncol = (2 * varsTesting) + 1, nrow = 0)
            for (i in 1:nrow(matches)) {
              player1_index <- matches[i, 1]
              player2_index <- matches[i, 2]
              fitness1 = result[player1_index, "CombinedFitness"]
              fitness2 = result[player2_index, "CombinedFitness"]
              tempVector = c(1, fitness1, fitness2)
              if (varsTesting > 1) {
                skill1 = result[player1_index, "CombinedSkill"]
                skill2 = result[player2_index, "CombinedSkill"]
                tempVector = c(tempVector, skill1, skill2)
              } 
              if (varsTesting > 2) {
                height1 = result[player1_index, "CombinedHeight"]
                height2 = result[player2_index, "CombinedHeight"]
                tempVector = c(tempVector, height1, height2)
              }
              if (varsTesting > 3) {
                age1 = result[player1_index, "CombinedAge"]
                age2 = result[player2_index, "CombinedAge"]
                tempVector = c(tempVector, age1, age2)
              }
              if (varsTesting > 4) {
                equipment1 = result[player1_index, "CombinedEquipment"]
                equipment2 = result[player2_index, "CombinedEquipment"]
                tempVector = c(tempVector, equipment1, equipment2)
              } 
              design = rbind(design, t(tempVector))
              if (D) {
                newDesignD = rbind(baseDesignD, design)
                fimD = t(newDesignD) %*% newDesignD
                det = det(fimD)
                if (det > bestDet) {
                  bestDet = det
                  newBestDesign = newDesignD
                  bestMatches = matches
                  bestPairs = pairs
                }
              }
              if (!D) {
                newDesignC = rbind(baseDesignC, design)
                fimC = t(newDesignC) %*% newDesignC
                inv = solve(fimC)
                invWeighted = 0
                for (i in 1:length(CWeight)) {
                  invWeighted = invWeighted + (CWeight[i] * inv[i, i]) 
                }
                if (invWeighted < bestInv) {
                  bestInv = invWeighted
                  newBestDesignC = newDesignC
                  bestMatchesC = matches
                  bestPairsC = pairs
                }
              }      
            }  
          }  
          if (D) {
            baseDesignD = newBestDesign
          }
          if (!D) {
            baseDesignC = newBestDesignC
          }
          incProgress(1/rounds)
          
          roundNum = k + 1
          outputString = paste(outputString, "Round ", roundNum, ":\n")
          if (D) {
            for (i in 1:nrow(bestMatches)) {
              pair1_idx <- bestMatches[i, 1]
              pair2_idx <- bestMatches[i, 2]
              pair1_players <- bestPairs[pair1_idx, ]
              pair2_players <- bestPairs[pair2_idx, ]
              outputString <- paste(outputString, "Player", pair1_players[1], "and", pair1_players[2], "vs Player",    pair2_players[1], "and", pair2_players[2], "\n")
            }
          }
          if (!D) {
            for (i in 1:nrow(bestMatchesC)) {
              pair1_idx <- bestMatchesC[i, 1]
              pair2_idx <- bestMatchesC[i, 2]
              pair1_players <- bestPairsC[pair1_idx, ]
              pair2_players <- bestPairsC[pair2_idx, ]
              outputString <- paste(outputString, "Player", pair1_players[1], "and", pair1_players[2], "vs Player",    pair2_players[1], "and", pair2_players[2], "\n")
            }
          }
        }
      }
      output$outputString <- renderText(outputString)
      if (D) {
        finalDesign(baseDesignD)
      }
      if (!D) {
        finalDesign(baseDesignC)
      }
      output$finalDesign = renderTable({finalDesign()})
      cat(outputString)
      calculation_done(TRUE)
      enable("downloadFile")
      enable("downloadDesign")
      enable("run")
      
      
      #Downloading Output File Function
      output$downloadFile <- downloadHandler(
        filename = function() {
          paste("output", ".txt", sep = "")
        },
        content = function(file) {
          writeLines(outputString, file)
        }
      )
      
      #Downloading Design 
      output$downloadCsv <- downloadHandler(
        filename = function() {
          paste("Tournament_Design", Sys.Date(), ".csv", sep = "")
        },
        content = function(file) {
          write.csv(finalDesign(), file, row.names = FALSE)
        }
      )
    })
  })
}

# Run the Shiny app
shinyApp(ui = ui, server = server)



