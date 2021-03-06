% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/cpi.R
\name{cpi}
\alias{cpi}
\title{Conditional Predictive Impact (CPI) for mlr.}
\usage{
cpi(task, learner, resampling = NULL, test_data = NULL,
  measure = NULL, test = "t", log = FALSE, B = 10000,
  alpha = 0.05, x_tilde = NULL, verbose = FALSE, cores = 1)
}
\arguments{
\item{task}{The prediction task.}

\item{learner}{The learner. If you pass a string the learner will be created via \link{makeLearner}.}

\item{resampling}{Resampling description object, mlr resampling strategy (e.g. \code{makeResampleDesc("Holdout")}), "oob" (out-of-bag) or "none" (in-sample loss).}

\item{test_data}{External validation data, use instead of resampling.}

\item{measure}{Performance measure.}

\item{test}{Statistical test to perform, either "t" (t-test), "fisher" (Fisher permuation test) or "bayes" (Bayesian testing, computationally intensive!).}

\item{log}{Set to \code{TRUE} for multiplicative CPI (\eqn{\lambda}), to \code{FALSE} for additive CPI (\eqn{\Delta}).}

\item{B}{Number of permutations for Fisher permutation test.}

\item{alpha}{Significance level for confidence intervals.}

\item{x_tilde}{Knockoff matrix. If not given (the default), it will be created with \link{create.second_order}.}

\item{verbose}{Verbose output of resampling procedure.}

\item{cores}{Number CPU cores used.}
}
\value{
For \code{test = "bayes"} a list of \code{BEST} objects. In any other cases a \code{data.frame} with a row for each feature and columns:
  \item{Variable}{Variable name}
  \item{CPI}{CPI value}
  \item{SE}{Standard error}
  \item{statistic}{Test statistic (t-test only)}
  \item{p.value}{p-value}
  \item{ci.lo}{Lower limit of confidence interval}
}
\description{
Conditional Predictive Impact (CPI) for mlr.
}
\examples{
library(mlr)
# Regression with linear model
bh.task.num <- dropFeatures(bh.task, "chas")
cpi(task = bh.task.num, learner = makeLearner("regr.lm"), 
    resampling = makeResampleDesc("Holdout"))

# Classification with logistic regression, log-loss and subsampling
cpi(task = iris.task, 
    learner = makeLearner("classif.glmnet", predict.type = "prob"), 
    resampling = makeResampleDesc("CV", iters = 5), 
    measure = "logloss", test = "t")
 
# Use your own data
mytask <- makeClassifTask(data = iris, target = "Species")
mylearner <- makeLearner("classif.ranger")
cpi(task = mytask, learner = mylearner, 
    resampling = makeResampleDesc("Subsample", iters = 5), 
    measure = "mmce", test = "fisher")
    
\dontrun{
# Bayesian testing
res <- cpi(task = iris.task, 
           learner = makeLearner("classif.glmnet", predict.type = "prob"), 
           resampling = makeResampleDesc("Holdout"), 
           measure = "logloss", test = "bayes")
plot(res$Petal.Length)
}   

}
