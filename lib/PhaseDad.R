############################################################################
# Get dad's phase based on phased or unphased moms and kids
# should return two haps

### link haplotypes
phasingDad <- function(dad_geno, mom_array, progeny, ped, win_length=10, errors=c(0.02, 0.8), 
                       verbose=TRUE, unphased_mom=FALSE, join_len=10){
    #dad_geno:
    #mom_array:
    #progeny:
    #win_length:
    #verbose:
    
    probs <- get_error_mat(hom.error=errors[1], het.error=errors[2])[[2]]
    
    #### phasing chunks
    haps <- setup_haps(win_length) 
    if(verbose){ message(sprintf("###>>> start to phase dad hap chunks ...")) }
    haplist <- phase_dad_chuck(dad_geno, mom_array, progeny, ped, haps, probs, verbose)
    
    #save(list=c("haplist", "mom_array", "progeny", "ped", "probs", "verbose"), file="largedata/haplist0.RData")
    #load("largedata/haplist0.RData")
    
    #### join chunks
    if(verbose){ message(sprintf("###>>> start to join hap chunks ...")) } 
    if(length(haplist) > 1){
        out <- join_dad_chunks(haplist, mom_array, progeny, ped, probs, verbose, unphased_mom, join_len)
        if(verbose){ message(sprintf("###>>> Reduced chunks from [ %s ] to [ %s ]", length(haplist), length(out))) } 
        haplist <- out
    }
    
    #### return data.frame
    out <- write_mom(haplist)
    hetsites <- which(dad_geno==1)
    if(verbose){ message(sprintf("###>>> phased [ %s (%s/%s) ] heter sites", 
                                 round(nrow(out)/length(hetsites),3), nrow(out), length(hetsites) )) } 
    return(out)
}

##########################################
join_dad_chunks <- function(haplist, mom_array, progeny, ped, probs, verbose, unphased_mom, join_len){
    outhaplist <- list(list())
    outhaplist[[1]] <- haplist[[1]] ### store the extended haps: hap1, hap2 and idx
    i <- 1
    for(chunki in 2:length(haplist)){
        if(verbose){ message(sprintf("###>>> join chunks [ %s and %s, total:%s] ...", chunki-1, chunki, length(haplist))) }
        # join two neighbor haplotype chunks
        oldchunk <- haplist[[chunki-1]]
        newchunk <- haplist[[chunki]]
        hapidx <- c(oldchunk[3], newchunk[3])
        dad_haps <- list(c(oldchunk[[1]], newchunk[[1]]), c(oldchunk[[1]], newchunk[[2]]))
        dad_haps_lofl <- list(list(oldchunk[[1]], newchunk[[1]]), list(oldchunk[[1]], newchunk[[2]]))
        
        ## link previous and current chunks
        temhap <- link_dad_haps(dad_haps_lofl, hapidx, mom_array, progeny, ped, unphased_mom, join_len, probs)
        temhap <- c(temhap[[1]], temhap[[2]])
        if(!is.null(temhap)){
            outold <- outhaplist[[i]][[1]]
            outoldchunk <- outold[ (length(outold)-length(oldchunk[[1]])+1):length(outold)]
            outnewchunk <- temhap[(length(oldchunk[[1]])+1):length(temhap)]
            
            same <- sum(outoldchunk == temhap[1:length(oldchunk[[1]])])
            #same <- sum(mom_phase1[(length(mom_phase1)-8):length(mom_phase1)] == win_hap[1:length(win_hap)-1])
            outhaplist[[i]][[3]] <- c(outhaplist[[i]][[3]], newchunk[[3]])
            if(same == 0){ #totally opposite phase of last window
                #hap2[length(mom_phase2)+1] <- win_hap[length(win_hap)]
                
                outhaplist[[i]][[1]] <- c(outhaplist[[i]][[1]], 1-outnewchunk)
                outhaplist[[i]][[2]] <- c(outhaplist[[i]][[2]], outnewchunk)
                
            } else if(same== length(oldchunk[[1]]) ){ #same phase as last window
                #mom_phase1[length(mom_phase1)+1] <- win_hap[length(win_hap)]
                
                outhaplist[[i]][[1]] <- c(outhaplist[[i]][[1]], outnewchunk)
                outhaplist[[i]][[2]] <- c(outhaplist[[i]][[2]], 1-outnewchunk)
            } else{
                stop(">>> Extending error !!!")
            }
        } else {
            i <- i +1
            outhaplist[[i]] <- haplist[[chunki]]
        } 
    }
    return(outhaplist)
}
#######
link_dad_haps <- function(dad_haps_lofl, hapidx, mom_array, progeny, ped, unphased_mom, join_len, probs){
    ### hapidx: a list of idx [[1]] chunk0; [[2]]chunk1
    
    
    phase_probs <- lapply(1:length(dad_haps_lofl), function(a) {
        max_joint_1hap(dad_hap=dad_haps_lofl[[a]], hapidx, mom_array, progeny, ped, unphased_mom, join_len, probs)
    } )
    phase_probs <- unlist(phase_probs)
    #if multiple haps tie, return two un-phased haps
    if(length(which(phase_probs==max(phase_probs)))>1){
        return(NULL)
    } else {
        return(dad_haps_lofl[[which.max(phase_probs)]])
    }
}

max_joint_1hap <- function(dad_hap, hapidx, mom_array, progeny, ped, unphased_mom, join_len, probs){
    ### log likely hood of one dad hap x all mom hap for all kids
    maxlog <- lapply(1:nrow(ped), function(x) {
        mymom <- mom_array[[ped$mom[x]]]
        myidx <- c(hapidx[[1]], hapidx[[2]])
        
        if(!is.null(nrow(mymom))){ #phased mom
            
            if(sum(mymom[myidx, ]$hap1 != mymom[myidx, ]$hap2) > 0){
                mom_haps <- list(mymom[myidx, ]$hap1, mymom[myidx, ]$hap2)
            }else{
                mom_haps <- list(mymom[mydix,]$hap1)
            }
            dad_hap <- c(dad_hap[[1]], dad_hap[[2]])
            kid_geno <- progeny[[x]][[2]][myidx]
            ####>>>
            max_log_1hap_1kid(dad_hap, mom_haps, kid_geno, probs)
            
        }else if(is.null(nrow(mymom)) & unphased_mom){ #unphased mom, default=TRUE
            mom_geno <- mymom[myidx]
            het_idx <- which(mom_geno==1)
            
            ### if mom het >10 reduce to 10 to reduce computational burden
            if(length(het_idx) > join_len){
                up_geno <- mymom[hapidx[[1]]]
                up_idx <- hapidx[[1]][up_geno==1]
                
                len2 <- join_len/2
                if(length(up_idx) > len2){
                    newidx1 <- hapidx[[1]][which(hapidx[[1]]==up_idx[length(up_idx)-len2+1]):length(hapidx[[1]])]
                    up_dad_hap <- dad_hap[[1]][which(hapidx[[1]]==up_idx[length(up_idx)-len2+1]):length(hapidx[[1]])]
                }else{
                    newidx1 <- hapidx[[1]] 
                    up_dad_hap <- dad_hap[[1]]
                }
                
                down_geno <- mymom[hapidx[[2]]]
                down_idx <- hapidx[[2]][down_geno==1]
                if(length(down_idx) > len2){
                    newidx2 <- hapidx[[2]][1:which(hapidx[[2]]==down_idx[len2])]
                    down_dad_hap <- dad_hap[[2]][1:which(hapidx[[2]]==down_idx[len2])]
                }else{
                    newidx2 <- hapidx[[2]]
                    down_dad_hap <- dad_hap[[2]]
                }
                
                dad_hap <- c(up_dad_hap, down_dad_hap)
                myidx <- c(newidx1, newidx2)
                mom_geno <- mymom[myidx]
                het_idx <- which(mom_geno==1)
            }else{
                dad_hap <- c(dad_hap[[1]], dad_hap[[2]])
            }

            if(length(het_idx) > 0 ){
                haps1 <- setup_haps(win_length=length(het_idx))
                haps2 <- lapply(1:length(haps1), function(x) 1-haps1[[x]])
                allhaps <- c(haps1, haps2)
                mom_haps <- vector("list", 2^length(het_idx))
                mom_haps <- lapply(1:length(mom_haps), function(x) {
                    temhap <- mom_geno/2
                    temhap[het_idx] <- allhaps[[x]]
                    return(temhap)})
            }else if(length(het_idx)==0){
                mom_haps <- list(mom_geno/2)
            }
            kid_geno <- progeny[[x]][[2]][myidx]
            ####>>>
            max_log_1hap_1kid(dad_hap, mom_haps, kid_geno, probs)
        }else{
            0
        }    
    })
    return(sum(unlist(maxlog)))
}
##########################################
phase_dad_chuck <- function(dad_geno, mom_array, progeny, ped, haps, probs, verbose){
    hetsites <- which(dad_geno==1)
    # gets all possible haplotypes for X hets 
    
    dad_phase1 = dad_phase2 = as.numeric() 
    win_hap = old_hap = nophase = as.numeric() 
    haplist <- list()
    
    winstart <- i <- 1
    ###### print progress bar
    pb <- txtProgressBar(min = winstart, max = length(hetsites)-(win_length-1), style = 3)
    while(winstart <= length(hetsites)-(win_length-1)){
        if(verbose){ setTxtProgressBar(pb, winstart) } 
        winidx <- hetsites[winstart:(winstart+win_length-1)]
        if(winstart==1){ 
            #arbitrarily assign win_hap to one chromosome initially
            # get the most likely dad haplotype, NULL is not allowed
            win_hap <- infer_dad_dip(winidx, mom_array, progeny, ped, haps, probs, returnhap=TRUE)
            dad_phase1 <- win_hap
            dad_phase2 <- 1-win_hap
            idxstart <- 1
        } else{
            win_hap <- infer_dad_dip(winidx, mom_array, progeny, ped, haps, probs, returnhap=FALSE)
            ### comparing current hap with old hap except the last bp for hap extension
            if(!is.null(win_hap)){
                
                same=sum(dad_phase1[(length(dad_phase1)-win_length+2):length(dad_phase1)]==win_hap[1:length(win_hap)-1])
                
                if(same == 0){ #totally opposite phase of last window
                    dad_phase2[length(dad_phase2)+1] <- win_hap[length(win_hap)]
                    dad_phase1[length(dad_phase1)+1] <- 1-win_hap[length(win_hap)]
                } else if(same==(win_length-1) ){ #same phase as last window
                    dad_phase1[length(dad_phase1)+1] <- win_hap[length(win_hap)]
                    dad_phase2[length(dad_phase2)+1] <- 1-win_hap[length(win_hap)]
                } else{
                    diff1 <- sum(abs(dad_phase1[(length(dad_phase1)-win_length+2):length(dad_phase1)]-win_hap[1:length(win_hap)-1]))
                    diff2 <- sum(abs(dad_phase2[(length(dad_phase1)-win_length+2):length(dad_phase1)]-win_hap[1:length(win_hap)-1]))
                    if(diff1 > diff2){ #dad_phase1 is less similar to current inferred hap
                        dad_phase2[length(dad_phase2)+1] <- win_hap[length(win_hap)]
                        dad_phase1[length(dad_phase1)+1] <- 1-win_hap[length(win_hap)]
                    } else{ #dad_phase1 is more similar
                        dad_phase1[length(dad_phase1)+1] <- win_hap[length(win_hap)]
                        dad_phase2[length(dad_phase2)+1] <- 1-win_hap[length(win_hap)]
                    }
                }
            } else {
                ### potential recombination in kids, output previous haps and jump to next non-overlap window -JLY###
                idxend <- winstart + win_length -2
                haplist[[i]] <- list(dad_phase1, dad_phase2, hetsites[idxstart:idxend])
                i <- i +1
                
                ### warning(paste("Likely recombination at position", winstart+1, sep=" "))
                ### if new window is still ambiguous, add 1bp and keep running until find the best hap
                winstart <- winstart + win_length -2
                while(is.null(win_hap)){
                    
                    winstart <- winstart + 1
                    win_hap <- jump_dad_win(winstart, win_length, hetsites, mom_array, progeny, ped, haps, probs)
                    if(is.null(win_hap)){
                        nophase <- c(nophase, hetsites[winstart])
                    }
                }
                idxstart <- winstart
                dad_phase1 <- win_hap
                dad_phase2 <- 1-win_hap
            }
        }
        winstart <- winstart + 1
    }
    close(pb)
    ### return the two haplotypes
    #myh1 <- replace(estimated_mom/2, hetsites, mom_phase1)
    #myh2 <- replace(estimated_mom/2, hetsites, 1-mom_phase1)
    #return(data.frame(h1=myh1, h2=myh2))
    #if(verbose){ message(sprintf(">>> phasing done!")) }
    haplist[[i]] <- list(dad_phase1, dad_phase2, hetsites[idxstart:length(hetsites)])
    ## list: hap1, hap2 and idx; info
    return(haplist)
    #return(list(haplist=haplist, info=list(het=hetsites, nophase=nophase)))
}

jump_dad_win <- function(winstart, win_length, hetsites, mom_array, progeny, ped, haps, probs){
    ### jump to next window
    if(length(hetsites) > (winstart + win_length - 1)){
        winidx <- hetsites[winstart:(winstart + win_length - 1)]
        win_hap <- infer_dad_dip(winidx, mom_array, progeny, ped, haps, probs, returnhap=FALSE)
    }else{
        winidx <- hetsites[winstart:length(hetsites)]
        mom_haps_tem <- setup_haps(win_length=length(winstart:length(hetsites)))
        win_hap <- infer_dad_dip(winidx, mom_array, progeny, ped, haps=mom_haps_tem, probs, returnhap=TRUE)
        
    }
    return(win_hap)
}

# Infer which phase is mom in a window
infer_dad_dip <- function(winidx, mom_array, progeny, ped, haps, probs, returnhap=FALSE){  
    # momwin is list of heterozygous sites, progeny list of kids genotypes, 
    # haps list of possible haps,momphase1 is current phased mom for use in splitting ties
    #### function for running one hap ####

    phase_probs <- lapply(1:length(haps), function(a) {sum_max_log_1hap(winidx, dad_hap=haps[[a]], ped, mom_array, progeny, probs)} )
    phase_probs <- unlist(phase_probs)
    #if multiple haps tie, check each against current phase and return one with smallest distance
    if(length(which(phase_probs==max(phase_probs)))>1){
        if(returnhap){
            return(haps[[sample(which(phase_probs==max(phase_probs)), 1)]])
        } else{
            return(NULL)
        }
    }else{
        return(haps[[which.max(phase_probs)]])
    } 
}

#### get the sum of the max log for each haplotype
sum_max_log_1hap <- function(winidx, dad_hap, ped, mom_array, progeny, probs){
    ### log likely hood of one dad hap x all mom hap for all kids
    maxlog <- lapply(1:nrow(ped), function(x) {
        mymom <- mom_array[[ped$mom[x]]]
        if(!is.null(nrow(mymom))){ #phased mom
            temmom <- mymom[winidx, ]
            if(length(unique(temmom$chunk))==1){
                mom_haps <- list(mymom[winidx, ]$hap1, mymom[winidx, ]$hap2)
            }else{
                haps1 <- setup_haps(length(unique(temmom$chunk)))
                haps2 <- lapply(1:length(haps1), function(x) 1-haps1[[x]])
                allhaps <- c(haps1, haps2)
                mom_haps <- lapply(1:length(allhaps), function(x){
                    
                    temout <- c()
                    k = 1
                    for(c in unique(temmom$chunk)){
                        temout <- c(temout, temmom[temmom$chunk==c, allhaps[[x]][k]+1])
                        k <- k+1
                    }
                    return(temout)    
                })
            }
            
        }else{ #unphased mom
            mom_geno <- mymom[winidx]
            het_idx <- which(mom_geno==1)
            if(length(het_idx) > 0){
                haps1 <- setup_haps(win_length=length(het_idx))
                haps2 <- lapply(1:length(haps1), function(x) 1-haps1[[x]])
                allhaps <- c(haps1, haps2)
                mom_haps <- vector("list", 2^length(het_idx))
                mom_haps <- lapply(1:length(mom_haps), function(x) {
                    temhap <- mom_geno/2
                    temhap[het_idx] <- allhaps[[x]]
                    return(temhap)})
            }else{
                mom_haps <- list(mom_geno/2)
            }   
        }
        kid_geno <- progeny[[x]][[2]][winidx]
        ####>>>
        max_log_1hap_1kid(dad_hap, mom_haps, kid_geno, probs)
    })
    return(sum(unlist(maxlog)))
} 
# Find most likely phase of kid at a window, return that probability
# give this dad haplotype, mom haplotypes and a kid's diploid genotype over the window and returns maximum prob
# Mendel is taken care of in the probs[[]] matrix already 
max_log_1hap_1kid <- function(dad_hap, mom_haps, kid_geno, probs){
    
    allgeno1 <- lapply(1:length(mom_haps), function(x) dad_hap + mom_haps[[x]])
    allgeno2 <- lapply(1:length(mom_haps), function(x) (1-dad_hap) + mom_haps[[x]])
    allgenos <- c(allgeno1, allgeno2)
    
    tem_mom_haps <- c(mom_haps, mom_haps)
    geno_probs <- lapply(1:length(allgenos), function(geno){
        #log(probs[[2]][three_genotypes,kidwin] is the log prob. of kid's obs geno 
        #given the current phased geno and given mom is het. (which is why probs[[2]])
        sum( unlist(lapply(1:length(dad_hap), function(zz) {
            if(tem_mom_haps[[geno]][zz] == 0){
                tem <- probs[[1]][allgenos[[geno]][zz]+1, kid_geno[zz]+1]
            }else if(tem_mom_haps[[geno]][zz] == 1){
                tem <- probs[[2]][allgenos[[geno]][zz]+1, kid_geno[zz]+1]
            }else if(tem_mom_haps[[geno]][zz] == 2){
                tem <- probs[[3]][allgenos[[geno]][zz]+1, kid_geno[zz]+1]
            }else if(tem_mom_haps[[geno]][zz] == 1.5){
                tem <- 1
            }
            return(log(tem))
            }))
        )   
    })
    ### may introduce error
    #if(length(which(geno_probs==max(geno_probs)))!=1){recover()}
    return(max(unlist(geno_probs)))
}
