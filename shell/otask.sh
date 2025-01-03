#!/usr/bin/env bash

random_delay() {
  local random_delay_max=$RandomDelay
  if [[ $random_delay_max ]] && [[ $random_delay_max -gt 0 ]]; then
    local file_param=$1
    local file_extensions=${RandomDelayFileExtensions-"js"}
    local ignored_minutes=${RandomDelayIgnoredMinutes-"0 30"}

    if [[ -n $file_extensions ]]; then
      if ! echo "$file_param" | grep -qE "\.${file_extensions// /$|\\.}$"; then
        # echo -e "\n当前文件需要准点运行, 放弃随机延迟\n"
        return
      fi
    fi

    local current_min
    current_min=$(date "+%-M")
    for minute in $ignored_minutes; do
      if [[ $current_min -eq $minute ]]; then
        # echo -e "\n当前时间需要准点运行, 放弃随机延迟\n"
        return
      fi
    done

    local delay_second=$(($(gen_random_num "$random_delay_max") + 1))
    echo -e "任务随机延迟 $delay_second 秒，配置文件参数 RandomDelay 置空可取消延迟 \n"
    sleep $delay_second
  fi
}

## scripts目录下所有可运行脚本数组
gen_array_scripts() {
  local dir_current=$(pwd)
  local i="-1"
  cd $dir_scripts
  for file in $(ls); do
    if [[ -f $file ]] && [[ $file == *.js && $file != sendNotify.js ]]; then
      let i++
      array_scripts[i]=$(echo "$file" | perl -pe "s|$dir_scripts/||g")
      array_scripts_name[i]=$(grep "new Env" $file | awk -F "\(" '{print $2}' | awk -F "\)" '{print $1}' | sed 's:.*\('\''\|"\)\([^"'\'']*\)\('\''\|"\).*:\2:' | sed 's:"::g' | sed "s:'::g" | head -1)
      [[ -z ${array_scripts_name[i]} ]] && array_scripts_name[i]="<未识别出活动名称>"
    fi
  done
  cd $dir_current
}

## 使用说明
usage() {
  gen_array_scripts
  echo -e "task命令运行本程序自动添加进crontab的脚本，需要输入脚本的绝对路径或去掉 “$dir_scripts/” 目录后的相对路径（定时任务中请写作相对路径），用法为："
  echo -e "1.$cmd_task <file_name>                                             # 依次执行，如果设置了随机延迟，将随机延迟一定秒数"
  echo -e "2.$cmd_task <file_name> now                                         # 依次执行，无论是否设置了随机延迟，均立即运行，前台会输出日志，同时记录在日志文件中"
  echo -e "3.$cmd_task <file_name> conc <环境变量名称> <账号编号，空格分隔>(可选的)  # 并发执行，无论是否设置了随机延迟，均立即运行，前台不产生日志，直接记录在日志文件中，且可指定账号执行"
  echo -e "4.$cmd_task <file_name> desi <环境变量名称> <账号编号，空格分隔>         # 指定账号执行，无论是否设置了随机延迟，均立即运行"
  if [[ ${#array_scripts[*]} -gt 0 ]]; then
    echo -e "\n当前有以下脚本可以运行:"
    for ((i = 0; i < ${#array_scripts[*]}; i++)); do
      echo -e "$(($i + 1)). ${array_scripts_name[i]}：${array_scripts[i]}"
    done
  else
    echo -e "\n暂无脚本可以执行"
  fi
}

## run nohup，$1：文件名，不含路径，带后缀
run_nohup() {
  local file_name=$1
  nohup node $file_name &>$log_path &
}

env_str_to_array() {
  . $file_env
  local IFS="&"
  read -ra array <<<"${!env_param}"
  array_length=${#array[@]}
  clear_env
}

clear_non_sh_env() {
  if [[ $file_param != *.sh ]]; then
    clear_env
  fi
}

## 正常运行单个脚本，$1：传入参数
run_normal() {
  local file_param=$1
  if [[ $# -eq 1 ]] && [[ "$real_time" != "true" ]] && [[ "$no_delay" != "true" ]]; then
    random_delay "$file_param"
  fi

  cd $dir_scripts
  local relative_path="${file_param%/*}"
  if [[ ${file_param} != /* ]] && [[ ! -z ${relative_path} ]] && [[ ${file_param} =~ "/" ]]; then
    cd ${relative_path}
    file_param=${file_param/$relative_path\//}
  fi

  if [[ $isJsOrPythonFile == 'false' ]]; then
    clear_non_sh_env
  fi
  $timeoutCmd $which_program $file_param "${script_params[@]}"
}

handle_env_split() {
  if [[ ! $num_param ]]; then
    num_param="1-max"
  fi

  env_str_to_array
  local tempArr=$(echo $num_param | sed "s/-max/-${array_length}/g" | sed "s/max-/${array_length}-/g" | perl -pe "s|(\d+)(-\|~\|_)(\d+)|{\1..\3}|g")
  local runArr=($(eval echo $tempArr))
  array_run=($(awk -v RS=' ' '!a[$1]++' <<<${runArr[@]}))
}

## 并发执行时，设定的 RandomDelay 不会生效，即所有任务立即执行
run_concurrent() {
  local file_param="$1"
  local env_param="$2"
  local num_param=$(echo "$3" | perl -pe "s|.*$2(.*)|\1|" | awk '{$1=$1};1')
  if [[ ! $env_param ]]; then
    echo -e "\n 缺少并发运行的环境变量参数"
    exit 1
  fi

  handle_env_split
  time=$(date "+$mtime_format")
  single_log_time=$(format_log_time "$mtime_format" "$time")

  cd $dir_scripts
  local relative_path="${file_param%/*}"
  if [[ ! -z ${relative_path} ]] && [[ ${file_param} =~ "/" ]]; then
    cd ${relative_path}
    file_param=${file_param/$relative_path\//}
  fi

  local j=0
  for i in ${array_run[@]}; do
    single_log_path="$dir_log/$log_dir/${single_log_time}_$((j + 1)).log"
    let j++

    if [[ $isJsOrPythonFile == 'false' ]]; then
      export "${env_param}=${array[$i - 1]}"
      clear_non_sh_env
    fi
    eval envParam="${env_param}" numParam="${i}" $timeoutCmd $which_program $file_param "${script_params[@]}" &>$single_log_path &
  done

  wait
  local k=0
  for i in ${array_run[@]}; do
    single_log_path="$dir_log/$log_dir/${single_log_time}_$((k + 1)).log"
    let k++
    cat $single_log_path
    [[ -f $single_log_path ]] && rm -f $single_log_path
  done
}

run_designated() {
  local file_param="$1"
  local env_param="$2"
  local num_param=$(echo "$3" | perl -pe "s|.*$2(.*)|\1|" | awk '{$1=$1};1')
  if [[ ! $env_param ]]; then
    echo -e "\n 缺少单独运行的参数 task xxx.js desi Test"
    exit 1
  fi

  handle_env_split

  if [[ $isJsOrPythonFile == 'false' ]]; then
    local n=0
    for i in ${array_run[@]}; do
      array_str[n]=${array[$i - 1]}
      let n++
    done
    local envStr=$(
      IFS="&"
      echo "${array_str[*]}"
    )
    [[ ! -z $envStr ]] && export "${env_param}=${envStr}"
    clear_non_sh_env
  fi

  cd $dir_scripts
  local relative_path="${file_param%/*}"
  if [[ ! -z ${relative_path} ]] && [[ ${file_param} =~ "/" ]]; then
    cd ${relative_path}
    file_param=${file_param/$relative_path\//}
  fi

  envParam="${env_param}" numParam="${num_param}" $timeoutCmd $which_program $file_param "${script_params[@]}"
}

## 运行其他命令
run_else() {
  local file_param="$1"

  cd $dir_scripts
  local relative_path="${file_param%/*}"
  if [[ ! -z ${relative_path} ]] && [[ ${file_param} =~ "/" ]]; then
    cd ${relative_path}
    file_param=${file_param/$relative_path\//.\/}
  fi

  shift

  clear_non_sh_env
  $timeoutCmd $which_program $file_param "$@"
}

check_file() {
  isJsOrPythonFile="false"
  if [[ $1 == *.js ]] || [[ $1 == *.mjs ]] || [[ $1 == *.py ]] || [[ $1 == *.pyc ]] || [[ $1 == *.ts ]]; then
    isJsOrPythonFile="true"
  fi
  if [[ -f $file_env ]]; then
    get_env_array
    if [[ $isJsOrPythonFile == 'true' ]]; then
      export PREV_NODE_OPTIONS="${NODE_OPTIONS:=}"
      export PREV_PYTHONPATH="${PYTHONPATH:=}"
      if [[ $1 == *.js ]] || [[ $1 == *.ts ]] || [[ $1 == *.mjs ]]; then
        export NODE_OPTIONS="-r ${file_preload_js} ${NODE_OPTIONS}"
      else
        export PYTHONPATH="${dir_preload}:${dir_config}:${PYTHONPATH}"
      fi
    else
      . $file_env
    fi
  fi
}

check_nounset() {
  local output=$(set -o)
  while read -r line; do
    if [[ "$line" =~ "nounset" ]] && [[ "$line" =~ "on" ]]; then
      set_u_on="true"
      set +u
      break
    fi
  done <<<"$output"
}

main() {
  if [[ $1 == *.js ]] || [[ $1 == *.py ]] || [[ $1 == *.pyc ]] || [[ $1 == *.sh ]] || [[ $1 == *.ts ]]; then
    if [[ $1 == *.sh ]]; then
      timeoutCmd=""
    fi

    case $# in
    1)
      run_normal "$1"
      ;;
    *)
      case $2 in
      now)
        run_normal "$1" "$2"
        ;;
      conc)
        run_concurrent "$1" "$3" "$*"
        ;;
      desi)
        run_designated "$1" "$3" "$*"
        ;;
      *)
        run_else "$@"
        ;;
      esac
      ;;
    esac
  elif [[ $# -eq 0 ]]; then
    echo
    usage
  else
    run_else "$@"
  fi
}

handle_task_start "${task_shell_params[@]}"
check_file "${task_shell_params[@]}"
if [[ $isJsOrPythonFile == 'false' ]]; then
  run_task_before "${task_shell_params[@]}"
fi
set_u_on="false"
check_nounset
main "${task_shell_params[@]}"
if [[ "$set_u_on" == 'true' ]]; then
  set -u
fi
if [[ $isJsOrPythonFile == 'true' ]]; then
  export NODE_OPTIONS="${PREV_NODE_OPTIONS}"
  export PYTHONPATH="${PREV_PYTHONPATH}"
fi
run_task_after "${task_shell_params[@]}"
clear_env
handle_task_end "${task_shell_params[@]}"
