

_mwp_complete()
{
  local cur prev OPTS
  local devs
  local mwpexts='@(TXT|BBL|mission|json|csv)'

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  case $prev in
    '-m'|'--mission')
      _mwp_files mission
      return 0
      ;;
    '-s'|'-d'|'serial-device'|'--device')
      devs=$(ls /dev/ttyUSB* /dev/ttyACM* /dev/rfcomm* 2> /dev/null)
      COMPREPLY=( $(compgen -W "$devs" -- $cur) )
      return 0
      ;;
    '-f'|'--flight-controller')
      COMPREPLY=( $(compgen -W "mw mwnav bf cf inav auto" -- $cur) )
      return 0
      ;;
    '-t'|'--force-type')
      COMPREPLY=( $(compgen -W '{1..26}'  -- $cur) )
      return 0
      ;;
    '-p'|'--replay-mwp')
      _mwp_files log
      return 0
      ;;
    '-b'|'--replay-bbox')
      _mwp_files TXT
      return 0
      ;;
    '-k'|'--kmlfile')
      _mwp_files KML
      return 0
      ;;
    '--centre')
      return 0
      ;;
    '--rebase')
      return 0
      ;;
    '-S'|'--n-points')
      return 0
      ;;
    '-M'|'--mod-points')
      return 0
      ;;
    '--rings')
      return 0
      ;;
    '--voice-command')
      return 0
      ;;

    '--forward-to')
      return 0
      ;;

    '--radar-device')
      return 0
      ;;

    '-h'|'--help'|'-V'|'--version'|'build-id')
      return 0
      ;;
  esac

  case $cur in
    -*)
      OPTS="--help
       	--mission
	--serial-device
	--device
	--flight-controller
	--connect
	--auto-connect
	--no-poll
	--no-trail
	--raw-log
	--ignore-sizing
	--full-screen
	--ignore-rotation
	--dont-maximise
	--force-mag
	--force-nav
	--layout
	--force-type
	--force4
	--ignore-3dr
	--centre-on-home
	--debug-flags
	--replay-mwp
	--replay-bbox
	--centre
	--offline
	--n-points
	--mod-points
	--rings
	--voice-command
	--version
	--build-id
	--really-really-run-as-root
	--forward-to
	--perma-warn
	--radar-device
	--fsmenu
	--kmlfile
	--relaxed-msp"

      COMPREPLY=( $(compgen -W "${OPTS[*]}" -- $cur) )
      return 0
      ;;
  esac
  _filedir "$mwpexts"

}
complete -F _mwp_complete mwp

_mwp_files()
{
  local path
  local wanted
  local cur
  wanted=$1
  _get_comp_words_by_ref cur;

  if [ -z "$cur" ]
  then
    case $wanted in
      'mission')
	path=$(dequote $(gsettings get  org.mwptools.planner mission-path))
	;;
      'log'|'TXT')
	path=$(dequote $(gsettings get  org.mwptools.planner log-path))
	;;
    esac
    if [ -n "$path" ] ; then
      cur="$path"
    else
      cur="$(pwd)"
    fi
  fi
  case $wanted in
    'mission')
      _filedir '@(json|mission)'
      ;;
    'TXT')
      _filedir '@(txt|TXT|bbl|BBL)'
      ;;
    'log')
      _filedir '@(log|LOG)'
      ;;
    'KML')
      _filedir '@(kml|KML)'
      ;;
  esac
}
