#!/bin/bash
set -e
set -u

LOG_DIR="!{task.process}"
if [ "!{params.dry_run}" == "true" ]; then
    mkdir !{reference_name}
    touch !{reference_name}/call_variants.dry_run.txt
else
    mkdir -p ${LOG_DIR}
    echo "# Timestamp" > ${LOG_DIR}/!{task.process}.versions
    date --iso-8601=seconds >> ${LOG_DIR}/!{task.process}.versions
    echo "# Snippy Version" >> ${LOG_DIR}/!{task.process}.versions
    snippy --version >> ${LOG_DIR}/!{task.process}.versions 2>&1

    snippy !{fastq} \
        --ref !{reference} \
        --cpus !{task.cpus} \
        --ram !{snippy_ram} \
        --outdir !{reference_name} \
        --prefix !{sample} \
        --mapqual !{params.mapqual} \
        --basequal !{params.basequal} \
        --mincov !{params.mincov} \
        --minfrac !{params.minfrac} \
        --minqual !{params.minqual} \
        --maxsoft !{params.maxsoft} !{bwaopt} !{fbopt} > ${LOG_DIR}/snippy.out 2> ${LOG_DIR}/snippy.err

    # Add GenBank annotations
    echo "# vcf-annotator Version" >> ${LOG_DIR}/!{task.process}.versions
    vcf-annotator --version >> ${LOG_DIR}/!{task.process}.versions 2>&1
    vcf-annotator !{reference_name}/!{sample}.vcf !{reference} > !{reference_name}/!{sample}.annotated.vcf 2> ${LOG_DIR}/vcf-annotator.err

    # Get per-base coverage
    echo "# bedtools Version" >> ${LOG_DIR}/!{task.process}.versions
    bedtools --version >> ${LOG_DIR}/!{task.process}.versions 2>&1
    grep "^##contig" !{reference_name}/!{sample}.vcf > !{reference_name}/!{sample}.coverage.txt
    genomeCoverageBed -ibam !{reference_name}/!{sample}.bam -d | cut -f3 >> !{reference_name}/!{sample}.coverage.txt 2> ${LOG_DIR}/genomeCoverageBed.err

    # Mask low coverage regions
    mask-consensus.py !{sample} !{reference_name} \
                      !{reference_name}/!{sample}.consensus.subs.fa \
                      !{reference_name}/!{sample}.subs.vcf \
                      !{reference_name}/!{sample}.coverage.txt \
                      --mincov !{params.mincov} > !{reference_name}/!{sample}.consensus.subs.masked.fa 2> ${LOG_DIR}/mask-consensus.err

    # Clean Up
    rm -rf !{reference_name}/reference !{reference_name}/ref.fa* !{reference_name}/!{sample}.vcf.gz*

    if [[ !{params.compress} == "true" ]]; then
        find !{reference_name}/ -type f -not -name "*.bam*" -and -not -name "*.log*" -and -not -name "*.txt*" | \
            xargs -I {} pigz -n --best -p !{task.cpus} {}
        pigz -n --best -p !{task.cpus} !{reference_name}/!{sample}.coverage.txt
    fi

    if [ "!{params.skip_logs}" == "false" ]; then 
        cp .command.err ${LOG_DIR}/!{task.process}.err
        cp .command.out ${LOG_DIR}/!{task.process}.out
        cp .command.sh ${LOG_DIR}/!{task.process}.sh || :
        cp .command.trace ${LOG_DIR}/!{task.process}.trace || :
    else
        rm -rf ${LOG_DIR}/
    fi
fi
