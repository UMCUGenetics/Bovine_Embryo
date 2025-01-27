## This script is used to merge quality statistics produced by Aneufinder, Samtools idxstats and bcftools stats

args <- commandArgs(trailingOnly=TRUE)
samplesheet_file <- args[1]
input_folder <- args[2] # should be [project_folder]/Data/
resolution <- args[3] # bin size used to run aneufinder
merge_idxstats <- args[4] # TRUE/FALSE
merge_aneufinder <- args[5] # TRUE/FALSE
merge_VCFStats <- args[6] # TRUE/FALSE

if(merge_aneufinder == TRUE){
  library(AneuFinder)
}

library(GenomicRanges)

samplesheet <- read.delim(samplesheet_file, header = T, stringsAsFactors = F)
# Remove positive and negative controls:
samplesheet <- samplesheet[samplesheet$Embryo != "POS" & samplesheet$Embryo != "NEG",]

resolution <- as.numeric(resolution)

QC_folder <- paste(input_folder, "QC/", sep = "")
dir.create(QC_folder, showWarnings = F, recursive = T)

CNV_calls_folder <- paste(input_folder, "CNV_calls/", sep = "")
dir.create(CNV_calls_folder, showWarnings = F)

## Read and merge samtools idxstats output
if(merge_idxstats == TRUE){
  chromosomes <- c(1:29, "X", "Y")
  Merged_idxstats <- data.frame()
  reads_per_chromosome <- ""
  print("## Merging idxstats")
  
  for(sample in unique(samplesheet$Cell)){
    #print(sample)
    
    if(file.exists(paste(input_folder, "idxstats/", samplesheet$Run[samplesheet$Cell == sample], "/", sample, ".idxstats", sep  ="")) == TRUE){
      idxstats_sample <- read.delim(paste(input_folder, "idxstats/", samplesheet$Run[samplesheet$Cell == sample], "/", sample, ".idxstats", sep  =""), header = F, stringsAsFactors = F)
      
      # Select the main chromosomes:
      idxstats_sample <- idxstats_sample[which(idxstats_sample[,1] %in% chromosomes),]
      
      if(nrow(Merged_idxstats) == 0){
        Merged_idxstats <- idxstats_sample[,1:3]
        names(Merged_idxstats)[ncol(Merged_idxstats)] <- sample
      } else {
        Merged_idxstats <- merge(Merged_idxstats, idxstats_sample[,c(1,3)], by = "V1")
        names(Merged_idxstats)[ncol(Merged_idxstats)] <- sample
      }
    } else {
      print(paste("# File: ",input_folder, "idxstats/", samplesheet$Run[samplesheet$Cell == sample], "/", sample, ".idxstats NOT found", sep  =""))
    }
  }
  
  names(Merged_idxstats)[1] <- "chr"
  
  Raw_reads <- data.frame(Cell = names(colSums(Merged_idxstats[,(3:ncol(Merged_idxstats))])), Raw_reads = colSums(Merged_idxstats[,(3:ncol(Merged_idxstats))]))
  
  print(paste("# Writing: ", QC_folder, "Merged_idxstats.txt", sep = ""))
  write.table(Merged_idxstats[order(factor(Merged_idxstats[,1], levels = chromosomes)),], file = paste(QC_folder, "Merged_idxstats.txt", sep = ""), quote = F, sep = "\t", row.names = F)
}

# merge aneufinder metrics > merge CNVs?
if(merge_aneufinder == TRUE){
  ## Collect quality metrics generated by Aneufinder
  quality_metrics <- data.frame()
  StrandSeq_metrics <- data.frame()

  print("## Reading Aneufinder data")
  for(run in unique(samplesheet$Run)){
    print(run)
    aneufinder_output <- ifelse(length(grep("Strand-seq", x = unique(samplesheet[samplesheet$Run == run, "Method"])) > 0),
                                paste(input_folder, "Aneufinder/", run, "/MODELS-StrandSeq/method-edivisive/", sep = ""),
                                paste(input_folder, "Aneufinder/", run, "/MODELS/method-edivisive/", sep = ""))
    aneufinder_files <- list.files(aneufinder_output, full.names = T)
    print(paste("## Loading ", length(aneufinder_files[grep(pattern = paste("bam_binsize_", format(resolution, scientific = T), sep = ""), x = as.character(aneufinder_files), fixed = T)]), " Aneufinder files from folder: ", aneufinder_output, sep = ""))

    files_to_read <- aneufinder_files[grep(pattern = paste("bam_binsize_", format(resolution, scientific = T), sep = ""), x = as.character(aneufinder_files), fixed = T)]
    aneufinder_data <- loadFromFiles(files_to_read)

    if(length(aneufinder_data) > 0){
      for(aneufinder_file in names(aneufinder_data)){
        #print(aneufinder_file)
        quality_cell <- as.data.frame(aneufinder_data[[aneufinder_file]]$qualityInfo)
        quality_cell$Cell <- gsub(x = aneufinder_data[[aneufinder_file]]$ID, pattern = ".bam", replacement = "")

        # Determine the most common copy number state in the cell according to aneufinder
        if(quality_cell$total.read.count > 0){
          quality_cell$base_cn_state <- median(aneufinder_data[[aneufinder_file]]$bins$copy.number)
          
        } else {
          quality_cell$base_cn_state <- 0
        }
        
        nullosomies <- aneufinder_data[[aneufinder_file]]$segments[aneufinder_data[[aneufinder_file]]$segments$state == "0-somy"]
        
        quality_cell$nullosomies <- ifelse(!is.null(nullosomies), length(nullosomies[which(width(nullosomies) > 25e6),]), 0)
        
        quality_metrics <- rbind(quality_metrics,quality_cell)
        
        # collect the copy number states for later haploid check:
        if(unique(samplesheet[samplesheet$Run == run, "Method"]) == "Strand-seq"){
          aneufinder_data_cell <- aneufinder_data[[aneufinder_file]]
          overview_cell <- data.frame(Cell = gsub(pattern = ".bam", replacement = "", x = aneufinder_data_cell$ID), 
                                      reads = aneufinder_data_cell$qualityInfo$total.read.count,
                                      somy0 = length(which(aneufinder_data_cell$segments$state == "0-somy")), 
                                      somy1 = length(which(aneufinder_data_cell$segments$state == "1-somy")), 
                                      somy2 = length(which(aneufinder_data_cell$segments$state == "2-somy")),
                                      somy3 = length(which(aneufinder_data_cell$segments$state == "3-somy")), 
                                      somy4 = length(which(aneufinder_data_cell$segments$state == "4-somy")),
                                      Watson_Crick = length(which(aneufinder_data_cell$segments$mcopy.number == aneufinder_data_cell$segments$pcopy.number & aneufinder_data_cell$segments$copy.number != 0)),
                                      Not_Watson_Crick = length(which(aneufinder_data_cell$segments$mcopy.number != aneufinder_data_cell$segments$pcopy.number & aneufinder_data_cell$segments$copy.number != 0)))
          StrandSeq_metrics <- rbind(StrandSeq_metrics, overview_cell)
        }
        
        # Write the raw CNV calls made by Aneufinder
        CNV_calls_cell <- as.data.frame(aneufinder_data[[aneufinder_file]]$segments[aneufinder_data[[aneufinder_file]]$segments$copy.number !=  quality_cell$base_cn_state])
        if(nrow(CNV_calls_cell)>0){
          
          CNV_Folder_Run <- paste(CNV_calls_folder, run, "/", sep = "")
          dir.create(CNV_Folder_Run, showWarnings = F)
          
          write.table(x = CNV_calls_cell, 
                      file = paste(CNV_Folder_Run,  gsub(pattern = ".bam", replacement = "", x = aneufinder_data[[aneufinder_file]]$ID), ".txt", sep = ""), 
                      quote = F, row.names = F, sep = "\t")
        }
      }
      #run_statistics <- data.frame(run = run, samples = length(aneufinder_files), high_read_depth = length(which(quality_metrics[quality_metrics$run == run, "total.read.count"]>150000)))
      #run_overview <- rbind(run_overview, run_statistics)
    } else {
      print(paste("# Aneufinder data not found: ", aneufinder_run, sep = ""))
    }
  }
  quality_output <- merge(samplesheet, quality_metrics, by = "Cell", all.x = T)
  
  # BrdU is not always incorporated in the cells (for example if cell did not divide), leading to WGS libraries instead of Strand-seq libraries. These cells need to be treated differently in the analysis than strand-seq cells.
  # Detect these cells and change their method:
  StrandSeq_metrics$WC_distribution <- StrandSeq_metrics$Watson_Crick / (StrandSeq_metrics$Watson_Crick + StrandSeq_metrics$Not_Watson_Crick)
  StrandSeq_metrics$Method <- ifelse(StrandSeq_metrics$WC_distribution > 0.7, "WGS_Strand-seq", "Strand-seq")
  StrandSeq_metrics$number_segments <- rowSums(StrandSeq_metrics[,c("somy0","somy1","somy2","somy3","somy4")])
  
  SS_WGS_cells <- StrandSeq_metrics$Cell[which(StrandSeq_metrics$WC_distribution > 0.7)]
  quality_output$Method[quality_output$Cell %in% SS_WGS_cells] <- "WGS_Strand-seq"
  quality_output <- merge(quality_output, Raw_reads, by = "Cell", all.x = T)
  # Write output files
  print(paste("# Writing: ", QC_folder, "Merged_quality_metrics.txt", sep = ""))
  write.table(x = quality_output, file = paste(QC_folder, "Merged_quality_metrics.txt", sep = ""), quote = F, row.names = F, sep = "\t")
  if(nrow(StrandSeq_metrics) > 0){
    print(paste("# Writing: ", QC_folder, "Merged_StrandSeq_metrics.txt", sep = ""))
    write.table(x = StrandSeq_metrics, file = paste(QC_folder, "Merged_StrandSeq_metrics.txt", sep = ""), quote = F, row.names = F, sep = "\t")
  }
}

# merge SNV stats
if(merge_VCFStats == TRUE){
  
  SNP_overview <- data.frame(stringsAsFactors = F)
  print("## Reading bcftools variant check files")
  
  VCF_Stats_Folder <- paste(input_folder, "SNVs/SNPs_Blastomeres/VCF_Stats/", sep = "")
  for(run in unique(samplesheet$Run)){
    VCF_Stats_Folder_Run <- paste(VCF_Stats_Folder, as.character(run), "/", sep = "")    
    print(VCF_Stats_Folder_Run)
    for(Cell in unique(samplesheet$Cell[samplesheet$Run == run])){
      variant_check_file <- list.files(VCF_Stats_Folder_Run, full.names = T)[grep(pattern = paste(Cell, ".vchk", sep = ""), x = list.files(VCF_Stats_Folder_Run))]
      if(file.exists(variant_check_file) == TRUE){
        variant_check_cell <- read.delim(variant_check_file,  header = F, comment.char = "#", stringsAsFactors = F)
        AF_cell <- variant_check_cell[which(variant_check_cell[,1] == "AF"),]
        if(nrow(AF_cell) > 0){
          SNPs_cell <- data.frame(Cell = Cell,
                                  Total_SNPs = variant_check_cell[variant_check_cell[,3] == "number of records:", 4],
                                  REF_SNPs = variant_check_cell[variant_check_cell[,3] == "number of no-ALTs:", 4],
                                  ALT_SNPs = variant_check_cell[variant_check_cell[,3] == "number of SNPs:", 4],
                                  
                                  AF0 = ifelse(as.numeric(AF_cell[1,3]) > 0, 0, AF_cell[1,4]),
                                  AF1 = ifelse(as.numeric(AF_cell[1,3]) > 0, AF_cell[1,4], AF_cell[2,4]),
                                  
                                  DP1 = ifelse(nrow( variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 1)+1,]) > 0, 
                                               variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 1)+1,2], NA),
                                  DP2 = ifelse(nrow( variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 2)+1,]) > 0,
                                               variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 2)+1,2], NA),
                                  DP3 = ifelse(nrow( variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 3)+1,]) > 0,
                                               variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 3)+1,2], NA),
                                  DP4 = ifelse(nrow( variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 4)+1,]) > 0,
                                               variant_check_cell[which(variant_check_cell[,1] == "DP" & variant_check_cell[,3] == 4)+1,2], NA),
                                  DP5 = ifelse(nrow( variant_check_cell[which(variant_check_cell[,1] == "DP" & as.numeric(variant_check_cell[,3]) > 4)+1,]) > 0,
                                               sum(variant_check_cell[which(variant_check_cell[,1] == "DP" & as.numeric(variant_check_cell[,3]) > 4)+1,2]), NA),
                                  stringsAsFactors = F)
          SNP_overview <- rbind(SNP_overview, SNPs_cell)
      }
     
      } else {
        print(paste("No stats for cell: ", file, sep = ""))
      }
    }
  }
  
  
  ## Next load the vcfs for each sample
  # Required to see how many reads cover SNPs at the same or on the different strand (haploid cells should not have overlapping reads on the same strand)
  SNP_overview$SNPs_same_strand <- NA
  SNP_overview$SNPs_other_strand <- NA
  SNP_overview$AF0_Filtered <- NA
  SNP_overview$AF1_Filtered <- NA
  print("## Reading SNV vcfs")
  
  quality_metrics <- read.delim(paste(QC_folder, "Merged_quality_metrics.txt", sep = ""), stringsAsFactors = F)
  
  for(run in unique(samplesheet$Run)){
    print(run)
    vcf_folder <- paste(input_folder, "/SNVs/SNPs_Blastomeres/", run, "/", sep = "")
    
    for(vcf_file in list.files(vcf_folder, pattern = ".vcf.gz$")){
      #print(vcf_file)
      sample <- gsub(vcf_file, pattern = ".vcf.gz", replacement = "")
      
      if(nrow(samplesheet[which(samplesheet$Cell == sample),]) > 0){
        
          if(file.exists(paste(vcf_folder, vcf_file, sep = "")) == TRUE & file.info(paste(vcf_folder, vcf_file, sep = ""))$size > 20000){
            vcf <- read.table(paste(vcf_folder, vcf_file, sep = ""), stringsAsFactors = F)
            # Exclude mitochondrial variants:
            vcf <- vcf[which(vcf[,1] != "MT"),]
            
            if(nrow(vcf) > 1){

              # The number of heterozygous SNPs is used to determine if a cell is haploid or not. 
              # Some SNPs may be caused by sequencing errors. Therefore we only want to select the SNPS that are called in multiple cells (eg PAC > 1)
              # In addition, some haploid cells may have some diploid/triploid regions, which may contain heterozygous SNPs. We want to exclude these regions from the het snp count
              
              #print(sample)
              
              CNV_Calls_file <- paste(CNV_calls_folder, run, "/", sample, ".txt", sep = "")
              if(file.exists(CNV_Calls_file)){
                CNV_Calls <- read.delim(CNV_Calls_file, header = T, stringsAsFactors = F)
                base_state <- quality_metrics$base_cn_state[quality_metrics$Cell == sample]
                gains <- CNV_Calls[which(CNV_Calls$copy.number > base_state),]
                
                if(nrow(gains) > 0 ){
                  
                  vcf_g <- GRanges(seqnames = vcf$V1, IRanges(start = vcf$V2, end = vcf$V2))
                  gains_g <- GRanges(seqnames = gains$seqnames[!is.na(gains$seqnames)], IRanges(start = gains$start[!is.na(gains$seqnames)], end = gains$end[!is.na(gains$seqnames)]))
                  
                  overlap_SNPs_gains <- findOverlaps(vcf_g, gains_g)
                  vcf <- vcf[-queryHits(overlap_SNPs_gains),]
                }
              }
              
              DP4 <- unlist(strsplit(vcf$V8, split = ";"))[grep("DP4=", x = unlist(strsplit(vcf$V8, split = ";")))]
              DP4 <- gsub(x = DP4, pattern = "DP4=", replacement = "")
              
              #DP4 = Number of 1) forward ref alleles; 2) reverse ref; 3) forward non-ref; 4) reverse non-ref alleles, used in variant calling. Sum can be smaller than DP because low-quality bases are not counted.
              # In theory there should not be reads on the same strand in the genome data a haploid cell sequenced with direct library prep
              # Now including both homozygous and heterozygous positions
              SNP_overview$SNPs_same_strand[which(SNP_overview$Cell == sample)] <- length(which(DP4 %in% c("1,0,1,0", "0,1,0,1", 
                                                                                                              "0,2,0,0", "2,0,0,0", 
                                                                                                              "0,0,2,0", "0,0,0,2")))
              SNP_overview$SNPs_other_strand[which(SNP_overview$Cell == sample)] <- length(which(DP4 %in% c("1,1,0,0", "0,0,1,1", "1,0,0,1", "0,1,1,0")))
              
              
              het_SNPs <- vcf[grep(pattern = "0/1", x = vcf[,10]),]
              # if(nrow(het_SNPs) > 0){
              #   PAC_het_SNPs <- unlist(strsplit(het_SNPs$V8, split = ";"))[grep("PAC=", x = unlist(strsplit(het_SNPs$V8, split = ";")))]
              #   PAC_het_SNPs <- strsplit(gsub(x = PAC_het_SNPs, pattern = "PAC=", replacement = ""), split = ",")
              #   
              #   if(length(PAC_het_SNPs) == nrow(het_SNPs)){
              #     het_SNPs$REF_counts <- matrix(unlist(PAC_het_SNPs),ncol = 2, byrow=TRUE)[,1]
              #     het_SNPs$ALT_counts <- matrix(unlist(PAC_het_SNPs),ncol = 2, byrow=TRUE)[,2]
              #     het_SNPs <- het_SNPs[which(het_SNPs$ALT_counts > 1 & het_SNPs$REF_counts > 1),]
              #   }
              # }
              
              SNP_overview$AF0_Filtered[which(SNP_overview$Cell == sample)] <- nrow(het_SNPs)
              SNP_overview$AF1_Filtered[which(SNP_overview$Cell == sample)] <- nrow(vcf[grep(pattern = ("1/1|0/0"), x = vcf$V10),])
            }
          }
      }
    }
  }
  # Most SNPs are "homozygous" because they are only covered by one read
  SNP_overview$Het_Hom <- as.numeric(SNP_overview$AF0_Filtered) / as.numeric(SNP_overview$AF1_Filtered)
  #SNP_overview$Het_Hom_corrected <- SNP_overview$Het_Hom / (SNP_overview$Total_SNPs / SNP_overview$total.read.count)
  
  # Heterozygosity is the portion of SNPs that are covered by two reads and in heterozygous state
  SNP_overview$Heterozygosity <- SNP_overview$AF0_Filtered / SNP_overview$DP2
  
  print(paste("# Writing: ", QC_folder, "Merged_SNP_Stats.txt", sep = ""))
  write.table(x = SNP_overview, file = paste(QC_folder, "Merged_SNP_Stats.txt", sep = ""), quote = F, row.names = F, sep = "\t")
}
