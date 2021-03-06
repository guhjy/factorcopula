#' Configurate the latent variables of a factorcopula model
#'
#' @param ... One or more expresssions separated by commas. The name of the expression arguments have to be
#' a valid random number generators, the expressions have to be lists of named unquoted arguments.#'
#' @param par a character vector of parameter names used in the specification of the factor matrix
#'
#' @return A list of \link[rlang]{quosure}s to be used in \link[factorcopula]{fc_create} or \link[factorcopula]{fc_fit}
#' @export
config_factor <- function(..., par = c()){
  factorspec <- rlang::exprs(...)
  fc_check(names(factorspec))
  list(spec = factorspec, par = par, fixed = (length(par) == 0))
}

#' Configurate the error part of a factorcopula model
#'
#' @param ... One named expresssion. The name has to be a
#' valid random number generator, the expression has to be a list of named unquoted arguments.
#' @param par a character vector of parameter names used in the specification of the factor matrix
#'
#' @return A list of \link[rlang]{quosure}s to be used in \link[factorcopula]{fc_create} or \link[factorcopula]{fc_fit}
#' @export
config_error <- function(..., par = c()){
  if (length(rlang::exprs(...)) > 1)
    stop("Only one error function allowed.")
  config_factor(..., par = par)
}

#' Configurate the loadings of a factorcopula model
#'
#' @param k Numeric vector of length N with eventually positive increasing integers from 1 to N.
#' @param Z Number of latent variables
#'
#' @return A character matrix of parameters to be used in \link[factorcopula]{fc_create} or \link[factorcopula]{fc_fit}
#' @export
config_beta <- function(k, Z = NULL){
  M <- max(k)
  N <- length(k)
  tab <- table(k)
  stopifnot(sum(tab) == N)
  stopifnot(length(tab) == M)
  stopifnot(all(as.numeric(names(tab)) == 1:M))

  if (M == N){# unrestrictive model
    stopifnot(!is.null(Z))
    return(matrix(paste0("beta", 1:(N*Z)), ncol = Z))
  }

  if (all(M == 1)){# equidependence
    stopifnot(!is.null(Z))
    return(matrix(rep(paste0("beta", 1:Z), each = N), ncol = Z, nrow = N))
  }

  # bloc- equidependence
  return(genBetaParMat(k))
}

#' Simulate values from a factor copula model
#'
#' @param factor a configuration specified by \link[factorcopula]{config_factor}
#' @param error a configuation specified by \link[factorcopula]{config_error}
#' @param beta a parameter matrix of factor loadings specified by \link[factorcopula]{config_beta}
#'
#' @return a function which can be used to simulate values from a factor copula model. It has the parameters theta, S and seed.
#' @export
fc_create <- function(factor, error, beta){
  force(factor)
  force(error)
  force(beta)

  N <- nrow(beta)
  Z <- length(factor$spec)
  stopifnot(ncol(beta) == Z, is.matrix(beta))

  state <- list(theta = -99, S = -99, zMat = matrix(-99), epsMat = matrix(-99), seed = NULL)


  function(theta, S, seed = NULL){
    set.seed(seed)
    if(state_changed(state, theta, S, factor$par, seed)){
      #cat("sim new Z values\n")
      zMat <- fc_sim(factor$spec, S, theta)
    } else{
      zMat <- state$zMat
    }

    if(state_changed(state, theta, S, error$par, seed)){
      #cat("sim new error values\n")
      epsMat <- fc_sim(error$spec, S*N, theta)
      epsMat <- matrix(epsMat, ncol = N)
    } else {
      epsMat <- state$epsMat
    }

    betaMat <- eval_beta(beta, theta)
    state <<- list(theta = theta, S = S, seed = seed, zMat = zMat, epsMat = epsMat)
    X <- zMat%*%t(betaMat) + epsMat
    apply(X, 2, empDist)
  }
}


state_changed <- function(state, theta, S, parnames, seed){
  if (is.null(seed)|(is.null(state$seed) & !is.null(seed)))
    res <- TRUE
  else {
    res <- any(seed != state$seed, state$S != S, length(parnames) != 0 && any(state$theta[parnames] != theta[parnames]))
  }
  return(res)
}

fc_sim <- function(config, S, theta){
  vapply(names(config), function(funName) {
    args <- config[[funName]]
    args <- rlang::eval_tidy(args, as.list(theta))
    args$n <- S
    do.call(funName, args)
  }, numeric(S))
}

eval_beta <- function(beta, theta){
  pos <- theta[beta]
  beta[!is.na(pos)] <- pos[!is.na(pos)]
  matrix(as.numeric(beta), ncol = ncol(beta))
}

fc_check <- function(names){
  if(any(names == ""))
    stop("At least one unnamed factor or error matrix config provided")
  for(name in names){
    if (!exists(name))
      stop("function '", name, "' does not exist")
  }
}

genBetaParMat <- function(k){
  kTab <- table(k)
  M <- max(k)
  first <- rep(paste0("beta", 1:M), times = kTab)
  last <- lapply(1:M, function(m){
    if (m == 1) timesLow <- 0 else timesLow <- sum(kTab[1:m-1])
    if (m == M) timesUp <- 0 else timesUp <- sum(kTab[(m+1):M])
    c(rep(0, timesLow), rep(paste0("beta", m+M), kTab[m]), rep(0, timesUp))
  })
  cbind(first, do.call(cbind, last))
}





