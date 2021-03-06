
#' Conditional Predictive Impact (CPI) for mlr.
#'
#' @param task The prediction task. 
#' @param learner The learner. If you pass a string the learner will be created via \link{makeLearner}.
#' @param resampling Resampling description object, mlr resampling strategy (e.g. \code{makeResampleDesc("Holdout")}), "oob" (out-of-bag) or "none" (in-sample loss).
#' @param test_data External validation data, use instead of resampling.
#' @param measure Performance measure. 
#' @param test Statistical test to perform, either "t" (t-test), "fisher" (Fisher permuation test) or "bayes" (Bayesian testing, computationally intensive!). 
#' @param log Set to \code{TRUE} for multiplicative CPI (\eqn{\lambda}), to \code{FALSE} for additive CPI (\eqn{\Delta}). 
#' @param B Number of permutations for Fisher permutation test.
#' @param alpha Significance level for confidence intervals.
#' @param x_tilde Knockoff matrix. If not given (the default), it will be created with \link{create.second_order}.
#' @param verbose Verbose output of resampling procedure.
#' @param cores Number CPU cores used.
#'
#' @return For \code{test = "bayes"} a list of \code{BEST} objects. In any other cases a \code{data.frame} with a row for each feature and columns:
#'   \item{Variable}{Variable name}
#'   \item{CPI}{CPI value}
#'   \item{SE}{Standard error}
#'   \item{statistic}{Test statistic (t-test only)}
#'   \item{p.value}{p-value}
#'   \item{ci.lo}{Lower limit of confidence interval}
#' 
#' @export
#' @import stats mlr foreach
#' @importFrom knockoff create.second_order
#'
#' @examples 
#' library(mlr)
#' # Regression with linear model
#' bh.task.num <- dropFeatures(bh.task, "chas")
#' cpi(task = bh.task.num, learner = makeLearner("regr.lm"), 
#'     resampling = makeResampleDesc("Holdout"))
#' 
#' # Classification with logistic regression, log-loss and subsampling
#' cpi(task = iris.task, 
#'     learner = makeLearner("classif.glmnet", predict.type = "prob"), 
#'     resampling = makeResampleDesc("CV", iters = 5), 
#'     measure = "logloss", test = "t")
#'  
#' # Use your own data
#' mytask <- makeClassifTask(data = iris, target = "Species")
#' mylearner <- makeLearner("classif.ranger")
#' cpi(task = mytask, learner = mylearner, 
#'     resampling = makeResampleDesc("Subsample", iters = 5), 
#'     measure = "mmce", test = "fisher")
#'     
#' \dontrun{
#' # Bayesian testing
#' res <- cpi(task = iris.task, 
#'            learner = makeLearner("classif.glmnet", predict.type = "prob"), 
#'            resampling = makeResampleDesc("Holdout"), 
#'            measure = "logloss", test = "bayes")
#' plot(res$Petal.Length)
#' }   
#' 
cpi <- function(task, learner, 
                resampling = NULL,
                test_data = NULL,
                measure = NULL,
                test = "t",
                log = FALSE,
                B = 10000,
                alpha = 0.05, 
                x_tilde = NULL,
                verbose = FALSE, 
                cores = 1) {
  if (is.null(measure)) {
    if (getTaskType(task) == "regr") {
      measure <- mse
    } else if (getTaskType(task) == "classif") {
      measure <- logloss
    } else {
      stop("Unknown task type.")
    }
  }
  
  if (is.character(measure)) {
    measure <- eval(parse(text = measure))
  }
  
  if (!(measure$id %in% c("mse", "mae", "mmce", "logloss", "brier"))) {
    stop("Currently only implemented for 'mse', 'mae', 'mmce', 'logloss' and 'brier' measures.")
  }
  if (!(test %in% c("t", "fisher"))) {
    stop("Currently only t-test (\"t\") and Fisher's exact test (\"fisher\") implemented.")
  }
  if (test == "bayes") {
    if (!requireNamespace("BEST", quietly = TRUE)) {
      stop("Package \"BEST\" needed for Bayesian testing. Please install it.",
           call. = FALSE)
    }
  }
  
  if (getTaskType(task) == "classif") {
    if (!hasLearnerProperties(learner, "prob")) {
      stop("For classification the learner requires probability support.")
    }
  }
  
  # Create resampling instance
  if (is.null(resampling)) {
    if (is.null(test_data)) {
      stop("Either resampling or test_data argument required.")
    }
  } else if (is.list(resampling)) {
    resample_instance <- makeResampleInstance(desc = resampling, task = task)
  } else if (resampling %in% c("none", "oob")) {
    resample_instance <- resampling
  } else {
    stop("Unknown resampling value.")
  }
  
  # Fit learner and compute performance
  fit_full <- fit_learner(learner = learner, task = task, resampling = resample_instance, measure = measure, test_data = test_data, verbose = verbose)
  pred_full <- predict_learner(fit_full, task, resampling = resample_instance, test_data = test_data)
  err_full <- compute_loss(pred_full, measure)
  
  # Generate knockoff data
  if (is.null(x_tilde)) {
    if (is.null(test_data)) {
      x_tilde <- knockoff::create.second_order(as.matrix(getTaskData(task)[, getTaskFeatureNames(task)]))
    } else {
      test_data_x_tilde <- knockoff::create.second_order(as.matrix(test_data[, getTaskFeatureNames(task)]))
    }
  } else if (is.matrix(x_tilde)) {
    if (is.null(test_data)) {
      if (any(dim(x_tilde) != dim(as.matrix(getTaskData(task)[, getTaskFeatureNames(task)])))) {
        stop("Size of 'x_tilde' must match dimensions of data.")
      }
    } else {
      if (any(dim(x_tilde) != dim(as.matrix(test_data[, getTaskFeatureNames(task)])))) {
        stop("Size of 'x_tilde' must match dimensions of data.")
      }
      test_data_x_tilde <- x_tilde
    }
  } else {
    stop("Argument 'x_tilde' must be a matrix or NULL.")
  }

  # For each feature, fit reduced model and return difference in error
  cpi_fun <- function(i) {
    if (is.null(test_data)) {
      reduced_test_data <- NULL
      reduced_data <- getTaskData(task)
      reduced_data[, getTaskFeatureNames(task)[i]] <- x_tilde[, getTaskFeatureNames(task)[i]]
      reduced_task <- changeData(task, reduced_data)
    } else {
      reduced_task <- NULL
      reduced_test_data <- test_data
      reduced_test_data[, getTaskFeatureNames(task)[i]] <- test_data_x_tilde[, getTaskFeatureNames(task)[i]]
    }
    
    # Predict with knockoff data
    pred_reduced <- predict_learner(fit_full, reduced_task, resampling = resample_instance, test_data = reduced_test_data)
    err_reduced <- compute_loss(pred_reduced, measure)
    if (log) {
      dif <- log(err_reduced / err_full)
    } else {
      dif <- err_reduced - err_full
    }
    cpi <- mean(dif)
    se <- sd(dif) / sqrt(length(dif))
    
    res <- data.frame(Variable = getTaskFeatureNames(task)[i],
                      CPI = unname(cpi), 
                      SE = unname(se),
                      stringsAsFactors = FALSE)
    
    # Statistical testing
    if (test == "fisher") {
      orig_mean <- mean(dif)
      
      # B permutations
      perm_means <- replicate(B, {
        signs <- sample(c(-1, 1), length(dif), replace = TRUE)
        mean(signs * dif)
      })
      res$p.value <- sum(perm_means >= orig_mean)/B
      res$ci.lo <- orig_mean - quantile(perm_means, 1 - alpha)
    } else if (test == "t") {
      test_result <- t.test(dif, alternative = 'greater')
      res$statistic <- test_result$statistic
      res$p.value <- test_result$p.value
      res$ci.lo <- test_result$conf.int[1]
    } else if (test == "bayes") {
      res <- list(BEST::BESTmcmc(dif, parallel = FALSE, verbose = FALSE))
      names(res) <- getTaskFeatureNames(task)[i]
    } else {
      stop("Unknown test.")
    }
    res
  }
  
  # Different return value for Bayesian testing
  if (test == "bayes") {
    .combine = c
  } else {
    .combine = rbind
  }
  
  # Run in parallel if >1 cores
  j <- NULL
  if (cores == 1) {
    foreach(j = seq_len(getTaskNFeats(task)), .combine = .combine) %do% cpi_fun(j)
  } else {
    foreach(j = seq_len(getTaskNFeats(task)), .combine = .combine) %dopar% cpi_fun(j)
  }
}




