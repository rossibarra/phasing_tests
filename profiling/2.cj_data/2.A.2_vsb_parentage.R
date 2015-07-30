### Jinliang Yang modified from VSB
### July 30th, 2015
## phasing.R

# load sequence lengths from chromosome
sl <- read.table("largedata/refgen2-lengths.txt", col.names=c("chrom", "length"),
                 stringsAsFactors = FALSE)
sl <- setNames(sl$length, sl$chrom)
chrs <- ifelse(names(sl) == "UNKNOWN", "0", names(sl))
names(sl) <- chrs
seqlengths(teo@ranges) <- sl[names(seqlengths(teo@ranges))]

## load in parent
parents <- read.delim("largedata/parent_taxa.txt", header=TRUE, stringsAsFactors=FALSE)
progeny <- read.delim("largedata/progeny_merged.txt", header=TRUE, stringsAsFactors=FALSE)

# all IDs found?
stopifnot(all(progeny$mother %in% parents$shorthand))


# all parent and progeny IDs in genotypes?
sample_names <- colnames(geno(teo))
stopifnot(all(parents$taxa %in% sample_names))
stopifnot(all(progeny$taxa %in% sample_names))

# stricter:
#length(setdiff(c(parents$taxa, progeny$taxa), sample_names))
#length(setdiff(sample_names, c(parents$taxa, progeny$taxa)))

## Load into ProgenyArray object

# mothers is given as an index to which column in parent genotype. Note that
# this is in the same order as the genotype columns (below) are ordered.
mothers <- match(progeny$mother, parents$shorthand)

pa <- ProgenyArray(geno(teo)[, progeny$taxa],
                   geno(teo)[, parents$taxa],
                   mothers,
                   loci=teo@ranges)
message("done.")
## Infer parentage
# calculate allele frequencies
pa <- calcFreqs(pa)

# infer parents
message("inferring parentage...  ", appendLF=FALSE)
pa <- inferParents(pa, ehet=0.6, ehom=0.1, verbose=TRUE)
message("done.")
message("saving parentage...  ", appendLF=FALSE)
save(pa, file=parentage_file)
message("done.")



