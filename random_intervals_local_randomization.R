# Local background model:
# All CNVs are relocated within 10Mb windows. This script generation of matrices with all random starts positions for all CNVs,  per segment

library( "regioneR" )
library( "BSgenome.Hsapiens.UCSC.hg19.masked" )
library( "seqbias" )

# Set working directory to Background-models
setwd("Background-models/")
if (!file.exists("local_random_intervals"))  dir.create(file.path(".", "local_random_intervals"))
if (!file.exists("local_random_intervals/output"))  dir.create(file.path("local_random_intervals", "output"))

# Load RData (deletion maps, intronic regions coordinates, gene coordinates, gene Ages)
load("deletions_introns_genes_ages.RData")

# Set working directory to Background-models

input_dir     <- "local_random_intervals/"
output_dir    <- "local_random_intervals/output/"
total_permuts <- 100 # 10000 in paper

# Datasets
all_CNV_sets <- c("Phase3_DELS",
                  "Handsaker_DELS",
                  "Zarrei_DELS",
                  "Abyzov_RANGES",
                  "Sud15_DELS")


## Retrieving genome and mask 
# Get genome and mask
human.genome    <- getGenomeAndMask(genome = "BSgenome.Hsapiens.UCSC.hg19.masked")$genome
human.autosomal <- filterChromosomes(human.genome, organism="hg", chr.type="autosomal")

# Filter genome and mask, only autosomes
human.mask <- getGenomeAndMask(genome = "BSgenome.Hsapiens.UCSC.hg19.masked")$mask
human.mask.autosomal <- filterChromosomes(human.mask, organism="hg", chr.type="autosomal")

### CNV datasets preparation
# Filtering CNV datasets
for(CNV_set in all_CNV_sets) {
  CNV_ranges <- get(CNV_set)
  # Pass all ranges to UCSC seqname style
  seqlevelsStyle(CNV_ranges)      <- "UCSC"
  # Only CNVs in autosomes
  CNV_ranges <- filterChromosomes(CNV_ranges, chr.type = "autosomal")
  # Not CNVs that overlap with low-mappability regions
  CNV_ranges <- CNV_ranges[!overlapsAny(CNV_ranges, human.mask.autosomal)]
  assign(CNV_set, CNV_ranges)
}


## As in Mu et al. 2011, we divide the genome in  windows of 10Mb (at least)
names(human.autosomal) <- seqnames(human.autosomal)
total_windows_per_chr  <- floor(end(human.autosomal)/10000000)
names(total_windows_per_chr) <- as.character(seqnames(human.autosomal))


segmented_autosomes <- c()
for(chr in as.character(seqnames(human.autosomal))) {
  breaks <- seq(0, 
                end(human.autosomal[chr]), 
                length.out = (total_windows_per_chr[chr]+1))
  df <- data.frame(seqnames = chr, 
                   start    = breaks[1:(length(breaks)-1)] +1,
                   end      = breaks[2:length(breaks)])
  segmented_autosomes <- rbind(segmented_autosomes,df)
}

segmented_autosomes <- makeGRangesFromDataFrame(segmented_autosomes)

names(segmented_autosomes) <- paste0("segment_", 1:length(segmented_autosomes))

# Determine which CNVs fall within segment
CNVs.with.center.in.segment <- function(whole_CNV_map, segment.coordinates, mask) {
  centre.ranges <- whole_CNV_map
  centre.coord <- round(apply(cbind(start(whole_CNV_map),
                                        end(whole_CNV_map)), 1, mean))
  start(centre.ranges) <- centre.coord
  end(centre.ranges)   <- centre.coord

  # Select CNVs with center in the segment
  cnvs.in.segment <- whole_CNV_map[overlapsAny(centre.ranges, segment.coordinates)]
 
  cnvs.in.segment
}



## LOCAL RANDOMIZATION
for(map_num in 1:5) {
  CNV_set <- all_CNV_sets[map_num]
  whole_CNV_map <- get(CNV_set)
  whole_granges <- GRanges()
  
  for(segment_num in 1:length(segmented_autosomes)) {
    
    segment.coordinates  = segmented_autosomes[segment_num]
    # Subset of cnvs in the segment
    subset_cnvs <- CNVs.with.center.in.segment(whole_CNV_map,
                                               segment.coordinates = segment.coordinates,
                                               mask = human.mask.autosomal)
  
    if(length(subset_cnvs) > 0) { 
      # Regions without mask
      mask_in_segment <- coverage(append(append(segment.coordinates,
                                                segment.coordinates),
                                         reduce(human.mask.autosomal)))
      # If there is mask coverage will be 3 or 1
      
      coverage_Rle <- mask_in_segment[[as.character(seqnames(segment.coordinates))]]
      # Transform to GRanges
      cov.granges <- GRanges(seqnames = as.character(seqnames(segment.coordinates)),
                             ranges= ranges(coverage_Rle),
                             coverage = coverage_Rle@values)
      # Select segment parts without mask
      unmasked_genome <- cov.granges[cov.granges$coverage == 2] 
      
      # adapt granges for random.intervals (each range will need a different seqname, and after it will need correction)
      
      unmasked_genome_for_randomization <- unmasked_genome
      
      # Transform chromosomes from chr- to number
      # seqlevelsStyle(unmasked_genome_for_randomization) <- "NCBI"
      chr_in_unmasked_genome <- as.character(unique(seqnames(unmasked_genome)))
      
      unmasked_genome_for_randomization <- GRanges(seqnames = 1:length(unmasked_genome_for_randomization),
                                                   ranges   = IRanges(start = start(unmasked_genome_for_randomization),
                                                                      end = end(unmasked_genome_for_randomization),
                                                                      names = 1:length(unmasked_genome_for_randomization)))
      
      all_random_starts <- c()
      
      for(i in 1:total_permuts) {
        # For some reason, random.intervals doesn't work if  length is 1, so in such cases we duplicate and remove later
        is_length_1 <- length(subset_cnvs) == 1
        if(is_length_1) {
          subset_cnvs <- append(subset_cnvs, subset_cnvs)
        }
        
        set.seed(map_num*10000000 + segment_num*10000 + i)
        random_int0 <- random.intervals(unmasked_genome_for_randomization,
                                        n=length(subset_cnvs),
                                        ms=width(subset_cnvs)-1)
        
        # This function has crated a randomized set giving the coordinates within the range. For example,
        # a CNV starting in position 2500 from  a range that starts with 2000 will be given as start  position 500.
        # Needs to be fixed. And also recover original seqnames, in this case will be the same for all
        random_int <- GRanges(seqnames = chr_in_unmasked_genome,
                              ranges = IRanges(start = start(random_int0) + start(unmasked_genome_for_randomization[seqnames(random_int0)]),
                                               end   = end(random_int0) + start(unmasked_genome_for_randomization[seqnames(random_int0)])))
        
        if(is_length_1) {
          random_int  <- random_int[1]
          subset_cnvs <- subset_cnvs[1]
        }
        
        all_random_starts <- cbind(all_random_starts, start(random_int))
        if(i%%1000 == 0) print(i)
      }
      
      # We save all random starts (chromosomes will be maintained in the randomization
      write.table(all_random_starts, quote = F, row.names = F, col.names = F,
                  file = paste0(output_dir, "local_random_intervals_random_starts_", CNV_set, 
                                "_subset_segment", segment_num, "_",
                                total_permuts, "_permuts.txt"))
      rm(all_random_starts)  
      
      if(segment_num%%10 == 0) print(paste("segment", segment_num, "of", length(segmented_autosomes)))
    }
 
    whole_granges <- append(whole_granges, subset_cnvs)
    
  }
  
  save(whole_granges,
       file = paste0(output_dir, "local_random_intervals_original_", CNV_set, "_GRanges.RData"))
                     
  print(CNV_set)
}
  


