#!/usr/bin/env bash

COL_NAMES="Class Name,Name,Filename,Start Pos,End Pos,Comment String Without Code,Implementation Without Comments,Implementation,Text"
TRAINING="flutter_docs_training.csv"
VALIDATION="flutter_docs_validation.csv"

dart bin/docs_data.dart --training "$TRAINING" --validation "$VALIDATION"

/google/bin/releases/tunelab/public/ingest_csv \
  --train_csv_file="$TRAINING" \
  --validation_csv_file="$VALIDATION" \
  --col_names="$COL_NAMES" \
  --dataset_name=flutter_doc_comments \
  --overwrite=true \
  --output_dir=/cns/sandbox/home/gspencer/datasets